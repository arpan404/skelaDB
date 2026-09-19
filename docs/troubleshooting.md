# Troubleshooting

## Install fails

- `images must be repository@sha256:<64 lowercase hex digits>` — every
  `SKELA_*_IMAGE` must be a digest reference, not a tag. Copy the values from
  the release verbatim.
- `set an installed CSI StorageClass` — `SKELA_STORAGE_CLASS` is empty or the
  class does not exist. Check with `kubectl get storageclass`.
- `skela-api Secret must have a nonempty token key` — create the Secret before
  `apply` (see [install](install.md#first-boot-secrets)).
- Rollout never finishes — `kubectl -n skela describe deploy/skela-control`
  and check events: usually image pull errors (add `SKELA_IMAGE_PULL_SECRET`)
  or a missing TLS issuer.

## Branch stuck in Pending / Starting

```sh
kubectl -n skela get br main -o yaml   # phase, events, backupPrefix
kubectl -n skela get pvc,statefulset,svc -l skeladb.io/branch=main
```

- No PVC: the StorageClass is wrong or out of capacity.
- Pod never ready: `kubectl -n skela logs statefulset/main` — usually a bad
  compute image or a fork whose parent is still suspended (parents wake
  automatically; wait a minute and re-check).
- Fork/restore refused: parent must be in the same project; `restore.at` must
  be RFC 3339 UTC; restore prefixes must stay inside the branch's project
  path.

## Connection refused or hangs

- Through the proxy: confirm the branch name in `options=branch=<name>` and
  that `phase` is `Running`. First connect after idle takes seconds while the
  compute resumes — retry; the proxy covers resume time.
- Wrong password after fork/restore: re-read `/connection` — the Secret is
  authoritative, the data directory's old password is not.
- Direct to the branch Service only works inside the cluster.

## Backups not appearing

`lastBackupAt` stays empty when the project backup Secret is missing or its
keys disagree with the provider (`s3`, `gcs`, `azure`). Check the controller
logs and the Secret keys in [install](install.md#project-credentials). At most
four backups run per controller — a backlog drains over successive
reconciles.

## License errors

- Controller won't start: the key is malformed — check for truncation when
  copying into the `skela-license` Secret.
- `402` on branch creation: expired key or branch/project limit reached.
  `/metrics` shows `skela_license_valid` and expiry. Running branches are
  never stopped by a lapsed license.

## Getting help

File an [issue](../../issues) with: release version, the redacted
`install.yaml` (strip the token first), `kubectl -n skela get br` output,
branch describe output and relevant logs. Never include Secrets, license keys
or connection strings.
