# SkelaDB

[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Releases](https://img.shields.io/github/v/release/arpan404/skeladb?label=releases)](releases/)

Serverless Postgres that runs in your own cloud account. Branches in
milliseconds, compute scales to zero when idle, history lives on cheap object
storage.

Learn more at [skeladb.com](https://skeladb.com) — see
[pricing](https://skeladb.com/pricing).

This repository is the public front door: install manifests, pinned releases
and issue tracking. The database source is private — you receive images, never
source.

## Quickstart

Prerequisites: a Kubernetes cluster, a backup bucket and image digests from a
[release](releases/). Full guide: [docs/install.md](docs/install.md).

```sh
SKELA_INSTALL_PROVIDER=aws \
SKELA_BACKUP_BUCKET=my-bucket \
SKELA_STORAGE_CLASS=skela-gp3 \
SKELA_CONTROL_IMAGE=ghcr.io/skeladb/control:0.0.1@sha256:<digest> \
SKELA_PROXY_IMAGE=ghcr.io/skeladb/proxy:0.0.1@sha256:<digest> \
SKELA_PG_IMAGE=ghcr.io/skeladb/postgres:18.4@sha256:<digest> \
./install.sh render > install.yaml   # inspect, then apply
SKELA_KUBE_CONTEXT=my-cluster ./install.sh apply
```

Create your first branch and connect (full guide: [docs/operations.md](docs/operations.md)):

```sh
API=$(kubectl -n skela get secret skela-api -o jsonpath='{.data.token}' | base64 -d)
kubectl -n skela port-forward svc/skela-control 8080 &
curl -s -H "Authorization: Bearer $API" -H 'Content-Type: application/json' \
  -d '{"name":"main","project":"demo"}' localhost:8080/v1/branches
URI=$(curl -s -H "Authorization: Bearer $API" \
  localhost:8080/v1/branches/main/connection | python3 -c 'import json,sys; print(json.load(sys.stdin)["uri"])')
psql "$URI" -c 'select version();'
```

## Layout

- `install.sh` — render or apply the platform from pinned image digests.
- `base/` — namespace, CRDs, RBAC, controller and proxy manifests.
- `aws/`, `gcp/`, `azure/`, `kubernetes/` — per-provider overlays.
- `tls/` — certificate management overlay for TLS and separated storage.
- `releases/` — one directory per version with digests and migration notes.
- `docs/` — [install](docs/install.md), [operations](docs/operations.md),
  [troubleshooting](docs/troubleshooting.md).

## Support

Stuck? Open an [issue](../../issues) with your release version, image digests,
Kubernetes version and redacted logs. Never paste secrets, license keys or
connection strings. Vulnerabilities go to security@skeladb.com —
see [SECURITY.md](SECURITY.md).

## License

Installer, manifests and docs here are Apache-2.0 (see `LICENSE`). Container
images are commercial software and require a license key for production.
