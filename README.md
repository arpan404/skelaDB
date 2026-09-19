# SkelaDB

[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Releases](https://img.shields.io/github/v/release/arpan404/skeladb?label=releases)](releases/)

Serverless Postgres that runs in your own cloud account. Branch in milliseconds,
scale to zero, pay object-storage prices for history.

Learn more at [skeladb.com](https://skeladb.com) — see
[pricing](https://skeladb.com/pricing) and [docs](https://skeladb.com/docs).

This is the public front door: install manifests, pinned releases and issue
tracking. The database source lives in a private repository — customers receive
images, never source.

## Install

You need an existing Kubernetes cluster (EKS, GKE, AKS or any CSI-backed
cluster), a backup bucket and released image digests from a [release](releases/).

```sh
SKELA_INSTALL_PROVIDER=aws \
SKELA_BACKUP_BUCKET=my-bucket \
SKELA_STORAGE_CLASS=skela-gp3 \
SKELA_CONTROL_IMAGE=ghcr.io/skeladb/control:0.0.1@sha256:<digest> \
SKELA_PROXY_IMAGE=ghcr.io/skeladb/proxy:0.0.1@sha256:<digest> \
SKELA_PG_IMAGE=ghcr.io/skeladb/postgres:18.4@sha256:<digest> \
./install.sh render > install.yaml   # inspect, then
./install.sh apply                   # installs into the skela namespace
```

Providers: `aws`, `gcp`, `azure`, `kubernetes`. Manifests live in
`base/` with per-provider overlays. Every image must be pinned by digest —
floating tags are refused. See `docs/` for provider setup, TLS and separated
storage options.

## Releases

Each version under `releases/` pins every image digest plus migration notes.
There is no `latest` tag.

## Support

Open an [issue](../../issues) with your release version, image digests,
Kubernetes version and redacted logs. Never paste secrets, license keys or
connection strings. See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

Install scripts, manifests and docs here are Apache-2.0 (see `LICENSE`).
Container images are commercial software under a separate license key.
