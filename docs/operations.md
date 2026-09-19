# Operations

Everything below goes through the control API. Authenticate every `/v1`
request with the token from install:

```sh
API=$(kubectl -n skela get secret skela-api -o jsonpath='{.data.token}' | base64 -d)
kubectl -n skela port-forward svc/skela-control 8080 &
BASE=localhost:8080 AUTH="Authorization: Bearer $API"
```

## Branches

A branch is a database: its own compute, credentials, backup schedule and
lifecycle. Names are lowercase, at most 48 characters.

```sh
# create (defaults: 500m CPU, 1Gi RAM, 10Gi storage, suspend after 5 min idle)
curl -s -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"name":"main","project":"demo"}' $BASE/v1/branches

# create with sizing and backup policy
curl -s -H "$AUTH" -H 'Content-Type: application/json' -d '{
  "name":"analytics","project":"demo","cpu":"2000m","memory":"4Gi",
  "storage":"100Gi","suspendAfterSeconds":60,
  "backupIntervalSeconds":21600}' $BASE/v1/branches

# list, describe
curl -s -H "$AUTH" "$BASE/v1/branches?project=demo"
curl -s -H "$AUTH" $BASE/v1/branches/main

# fork from another branch (copy-based)
curl -s -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"name":"experiment","project":"demo","parent":"main"}' $BASE/v1/branches

# delete (data is gone immediately; add ?purge_backups=true to also
# delete every backup and WAL segment of the branch)
curl -s -X DELETE -H "$AUTH" "$BASE/v1/branches/experiment?purge_backups=true"
```

`phase` is `Pending` → `Starting` → `Running`, or `Suspended` after
`suspendAfterSeconds` of idle time. Suspended branches cost nothing but
storage; they resume automatically on next connection.

Limits per call: JSON bodies ≤ 64 KiB, CPU 1m–64 cores, memory 128Mi–256Gi,
storage 1Gi–16Ti. A `402` means your license expired or you hit its branch /
project limit.

## Connecting

Ask for connection details — this also wakes a suspended branch:

```sh
curl -s -H "$AUTH" $BASE/v1/branches/main/connection
# {"host":"...","port":5432,"user":"postgres","password":"...","uri":"postgres://..."}
```

Connect through the proxy (port 6432 on its load balancer) so connections are
pooled and branches wake on connect:

```sh
psql "postgres://postgres:<password>@<proxy-host>:6432/main?options=branch%3Dmain" \
  -c 'select version();'
```

Routing is by the `branch=<name>` startup option, falling back to the first
DNS label of the server name. The per-branch password lives in the
`<name>-pg` Secret and is authoritative — use it, not the data directory's
old password, after forks and restores.

Direct port-forward to the branch Service (`<name>:5432`) works for debugging
but bypasses pooling and wake-on-connect.

## Backups and point-in-time recovery

Every branch archives WAL continuously and takes base backups every
`backupIntervalSeconds` (default 24h), keeping `backupRetainCount` full
backups (default 7). Check `backupPrefix` and `lastBackupAt` on the branch.

Restore to a new branch at a point in time:

```sh
# from a live branch's backups
curl -s -H "$AUTH" -H 'Content-Type: application/json' -d '{
  "name":"main-yesterday","project":"demo",
  "restore":{"from":"main","at":"2026-09-02T23:50:00Z"}}' $BASE/v1/branches

# from any backup prefix, including a deleted branch's
curl -s -H "$AUTH" -H 'Content-Type: application/json' -d '{
  "name":"forensics","project":"demo",
  "restore":{"prefix":"s3://my-bucket/skela/demo/main-0ebc9a3c",
              "at":"2026-09-02T23:50:00Z"}}' $BASE/v1/branches
```

Timestamps are RFC 3339 in UTC.

## Upgrading

Upgrades are digest swaps. Render the new release over the same variables and
apply:

```sh
# same env as install, with the new release's digests
./install.sh render > install.yaml   # diff it
SKELA_KUBE_CONTEXT=my-cluster ./install.sh apply
```

Rolling Deployments (controller, proxy) update in place. Branch computes keep
their configured image until you recreate the branch — plan compute image
changes as branch recreations, not in-place edits.

## Suspending and resuming

Idle branches suspend themselves. To force it, scale through the API by
setting `suspendAfterSeconds` low, or delete what you no longer need. To keep
a branch always warm, create it with `"suspendAfterSeconds":0`. Resume is
automatic on connect; watch `phase` move `Suspended` → `Starting` →
`Running`.

## Monitoring

- `GET /healthz` — liveness, no auth.
- `GET /metrics` — Prometheus text, no auth: per-phase branch gauges,
  backup totals and failures, license status.
- `kubectl -n skela get branches` (short name `br`) shows every branch and
  its phase.

## Uninstalling

Deleting a branch deletes its compute, volumes and credentials immediately —
backups in the bucket survive unless you purged them. To remove the platform,
delete the namespace (`kubectl delete namespace skela`) and then clean the
`<bucket>/skela/` prefixes you no longer need.
