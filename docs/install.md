# Install

`install.sh` renders the platform into one manifest (`render`) or applies it
to your cluster (`apply`). Everything is pinned by digest — floating tags are
refused.

## Prerequisites

- Kubernetes 1.29+ with a CSI StorageClass (EKS, GKE, AKS or any conformant
  cluster). For AWS, `aws/eksctl.yaml` is a ready cluster definition:
  `eksctl create cluster -f aws/eksctl.yaml`.
- A backup bucket: S3, GCS or Azure Blob. One bucket holds every project;
  access is scoped per project (see Project credentials below).
- Image digests from a [release](../releases/): control, proxy and Postgres at
  minimum. Copy the `SKELA_*_IMAGE` values verbatim.
- Tools: `kubectl`, `kustomize` (via `kubectl kustomize`), `openssl` for tokens.

## Render, inspect, apply

```sh
SKELA_INSTALL_PROVIDER=aws \
SKELA_BACKUP_BUCKET=my-bucket \
SKELA_STORAGE_CLASS=skela-gp3 \
SKELA_CONTROL_IMAGE=ghcr.io/skeladb/control:0.0.1@sha256:<digest> \
SKELA_PROXY_IMAGE=ghcr.io/skeladb/proxy:0.0.1@sha256:<digest> \
SKELA_PG_IMAGE=ghcr.io/skeladb/postgres:18.4@sha256:<digest> \
./install.sh render > install.yaml
```

Read `install.yaml`, then apply against an explicit context:

```sh
SKELA_KUBE_CONTEXT=my-cluster ./install.sh apply
```

`apply` verifies the StorageClass, the `skela-api` Secret (created on first
install — see below) and any pull secret or TLS issuer you configured, then
waits for the controller and proxy rollouts.

Providers (`SKELA_INSTALL_PROVIDER`): `aws`, `gcp`, `azure`, `kubernetes`.
`kubernetes` is the generic overlay (ClusterIP proxy); the cloud overlays add
an internal load balancer, storage class and backup wiring.

## First boot secrets

On first install create the API token before applying:

```sh
kubectl create namespace skela --dry-run=client -o yaml | kubectl apply -f -
kubectl -n skela create secret generic skela-api \
  --from-literal=token="$(openssl rand -hex 24)"
```

Keep that token somewhere safe — it is the admin credential for the control
API (see [operations](operations.md)).

## Project credentials

Each project needs a backup Secret (and on AWS/GCP, an identity binding):

- AWS (IRSA): a ServiceAccount `skela-backup-<project>` carrying the backup
  role, plus a Secret `skela-backup-<project>` with `SKELA_BACKUP_BUCKET` and
  `AWS_REGION`. The role may only touch `<bucket>/skela/<project>/*`.
- GCP: attach the workload-identity binding in `gcp/` and a Secret
  `skela-backup-<project>` with `SKELA_BACKUP_BUCKET`.
- Generic / access keys: a Secret `skela-backup-<project>` with
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`,
  `SKELA_BACKUP_BUCKET` (plus `AWS_ENDPOINT` and
  `AWS_S3_FORCE_PATH_STYLE=true` for S3-compatible stores).

Prefer one bucket with per-project prefixes (`SKELA_BACKUP_PER_PROJECT=1`
selects that mode and forbids `SKELA_BACKUP_BUCKET`).

## License key

Production needs a license key; without one the platform runs unlicensed for
evaluation. Create it as a Secret and wire it to the controller:

```sh
kubectl -n skela create secret generic skela-license \
  --from-literal=key="<license-token>"
```

The `aws/` overlay reads this Secret automatically. On other providers, set
`SKELA_LICENSE_KEY` on the `skela-control` Deployment to the same value.
An invalid key stops the controller at startup; an expired key stops new
branches but never stops running databases. License status is exposed in
`/metrics` (`skela_license_valid`, `skela_license_expiry_timestamp`).

## TLS

Set both to terminate the proxy and control plane with your issuer
(cert-manager `Issuer` in the `skela` namespace):

```sh
SKELA_TLS_ISSUER=my-issuer SKELA_TLS_DNS_NAME=db.example.com ./install.sh render
```

`SKELA_TLS_DNS_NAME` is the SQL hostname clients connect to.

## Separated storage

For the disaggregated engine (pageserver + WAL service instead of volumes on
each compute), add all three:

```sh
SKELA_PAGESERVER_IMAGE=...@sha256:<digest> \
SKELA_WAL_IMAGE=...@sha256:<digest> \
SKELA_TLS_ISSUER=my-issuer
```

Separated mode requires the TLS issuer (internal mTLS between compute and
storage). Per-Postgres-major images and `SKELA_PG_SEPARATED_MAJORS` select
which majors run separated; the default `SKELA_PG_IMAGE` covers the rest.

## Private registries

If images live behind authentication, pass
`SKELA_IMAGE_PULL_SECRET=<secret-name>` (a `kubernetes.io/dockerconfigjson`
Secret in `skela`). It is mounted on computes and storage pods.
