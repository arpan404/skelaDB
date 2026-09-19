#!/usr/bin/env bash
# Render or install released images into an existing Kubernetes cluster.
set -euo pipefail
cd "$(dirname "$0")"
mode=${1:-render}
case "$mode" in render|apply) ;; *) echo 'usage: deploy/install.sh [render|apply]' >&2; exit 1 ;; esac
provider=${SKELA_INSTALL_PROVIDER:-kubernetes}
case "$provider" in
    aws|kubernetes) backup_provider=s3 ;;
    gcp) backup_provider=gcs ;;
    azure) backup_provider=azure ;;
    *) echo 'SKELA_INSTALL_PROVIDER must be aws, gcp, azure or kubernetes' >&2; exit 1 ;;
esac
per_project=${SKELA_BACKUP_PER_PROJECT:-0}
case "$per_project" in
    0) : "${SKELA_BACKUP_BUCKET:?set the backup bucket or Azure container}" ;;
    1) [ -z "${SKELA_BACKUP_BUCKET:-}" ] || { echo 'unset SKELA_BACKUP_BUCKET with SKELA_BACKUP_PER_PROJECT=1' >&2; exit 1; } ;;
    *) echo 'SKELA_BACKUP_PER_PROJECT must be 0 or 1' >&2; exit 1 ;;
esac
: "${SKELA_STORAGE_CLASS:?set an installed CSI StorageClass}"
: "${SKELA_CONTROL_IMAGE:?set a released control image digest}"
: "${SKELA_PROXY_IMAGE:?set a released proxy image digest}"
: "${SKELA_PG_IMAGE:?set a released PostgreSQL image digest}"
for image in "$SKELA_CONTROL_IMAGE" "$SKELA_PROXY_IMAGE" "$SKELA_PG_IMAGE" ${SKELA_PG_12_IMAGE:+"$SKELA_PG_12_IMAGE"} ${SKELA_PG_13_IMAGE:+"$SKELA_PG_13_IMAGE"} ${SKELA_PG_14_IMAGE:+"$SKELA_PG_14_IMAGE"} ${SKELA_PG_15_IMAGE:+"$SKELA_PG_15_IMAGE"} ${SKELA_PG_16_IMAGE:+"$SKELA_PG_16_IMAGE"} ${SKELA_PG_17_IMAGE:+"$SKELA_PG_17_IMAGE"} ${SKELA_PG_19_IMAGE:+"$SKELA_PG_19_IMAGE"}; do
    [[ $image =~ ^[a-z0-9][a-z0-9./:_-]*@sha256:[a-f0-9]{64}$ ]] || {
        echo 'images must be repository@sha256:<64 lowercase hex digits>' >&2; exit 1;
    }
done
if [ -n "${SKELA_PAGESERVER_IMAGE:-}${SKELA_WAL_IMAGE:-}" ]; then
    : "${SKELA_PAGESERVER_IMAGE:?set the pageserver image digest}"
    : "${SKELA_WAL_IMAGE:?set the WAL service image digest}"
    : "${SKELA_TLS_ISSUER:?separated storage requires a certificate Issuer}"
    for image in "$SKELA_PAGESERVER_IMAGE" "$SKELA_WAL_IMAGE"; do
        [[ $image =~ ^[a-z0-9][a-z0-9./:_-]*@sha256:[a-f0-9]{64}$ ]] || {
            echo 'storage images must use sha256 digests' >&2; exit 1;
        }
    done
fi
if [ "$per_project" = 0 ]; then
[[ $SKELA_BACKUP_BUCKET =~ ^[a-z0-9][a-z0-9._-]*$ && ${#SKELA_BACKUP_BUCKET} -le 222 ]] || {
    echo 'invalid SKELA_BACKUP_BUCKET' >&2; exit 1;
}
fi
[[ $SKELA_STORAGE_CLASS =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && ${#SKELA_STORAGE_CLASS} -le 253 ]] || {
    echo 'invalid SKELA_STORAGE_CLASS' >&2; exit 1;
}
if [ "$provider" = azure ]; then
    [[ ${SKELA_BACKUP_AZURE_ACCOUNT:-} =~ ^[a-z0-9]{3,24}$ ]] || {
        echo 'set SKELA_BACKUP_AZURE_ACCOUNT to the Azure storage account name' >&2; exit 1;
    }
elif [ -n "${SKELA_BACKUP_AZURE_ACCOUNT:-}" ]; then
    echo 'SKELA_BACKUP_AZURE_ACCOUNT requires the azure provider' >&2; exit 1
fi
pull_secret=${SKELA_IMAGE_PULL_SECRET:-}
if [ -n "$pull_secret" ] && [[ ! $pull_secret =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
    echo 'invalid SKELA_IMAGE_PULL_SECRET' >&2; exit 1
fi
tls_issuer=${SKELA_TLS_ISSUER:-}
if [ -n "$tls_issuer" ]; then
    [[ $tls_issuer =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && ${#tls_issuer} -le 253 ]] || { echo 'invalid SKELA_TLS_ISSUER' >&2; exit 1; }
    [[ ${SKELA_TLS_DNS_NAME:-} =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && ${#SKELA_TLS_DNS_NAME} -le 253 ]] || { echo 'set SKELA_TLS_DNS_NAME to the SQL hostname' >&2; exit 1; }
elif [ -n "${SKELA_TLS_DNS_NAME:-}" ]; then
    echo 'SKELA_TLS_DNS_NAME requires SKELA_TLS_ISSUER' >&2; exit 1
fi
work=$(mktemp -d "$PWD/.install.XXXXXX")
trap 'rm -rf "$work"' EXIT
cat > "$work/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../$provider
images:
  - name: skeladb/control
    newName: ${SKELA_CONTROL_IMAGE%@*}
    digest: ${SKELA_CONTROL_IMAGE#*@}
  - name: skeladb/proxy
    newName: ${SKELA_PROXY_IMAGE%@*}
    digest: ${SKELA_PROXY_IMAGE#*@}
configMapGenerator:
  - name: skela-backup-config
    namespace: skela
    literals:
      - bucket=${SKELA_BACKUP_BUCKET:-}
patches:
  - path: control.yaml
YAML
cat > "$work/control.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skela-control
spec:
  template:
    spec:
      containers:
        - name: control
          env:
            - name: SKELA_PG_IMAGE
              value: $SKELA_PG_IMAGE
            - name: SKELA_IMAGE_PREFIX
              value: ""
            - name: SKELA_BACKUP_PROVIDER
              value: $backup_provider
            - name: SKELA_BACKUP_BUCKET
              valueFrom:
                configMapKeyRef: { name: skela-backup-config, key: bucket }
            - name: SKELA_STORAGE_CLASS
              value: $SKELA_STORAGE_CLASS
YAML
if [ -n "${SKELA_PG_SEPARATED_MAJORS:-}" ]; then
    [[ "$SKELA_PG_SEPARATED_MAJORS" =~ ^(12|13|14|15|16|17|18|19)(,(12|13|14|15|16|17|18|19))*$ ]] || { echo 'invalid SKELA_PG_SEPARATED_MAJORS' >&2; exit 1; }
    cat >> "$work/control.yaml" <<YAML
            - name: SKELA_PG_SEPARATED_MAJORS
              value: "$SKELA_PG_SEPARATED_MAJORS"
YAML
fi
for major in 12 13 14 15 16 17 19; do
    key="SKELA_PG_${major}_IMAGE"
    if [ -n "${!key:-}" ]; then
        cat >> "$work/control.yaml" <<YAML
            - name: $key
              value: ${!key}
YAML
    fi
done
if [ -n "${SKELA_PAGESERVER_IMAGE:-}" ]; then
    cat >> "$work/control.yaml" <<YAML
            - name: SKELA_PAGESERVER_IMAGE
              value: $SKELA_PAGESERVER_IMAGE
            - name: SKELA_WAL_IMAGE
              value: $SKELA_WAL_IMAGE
YAML
fi
if [ -n "$pull_secret" ]; then
    cat >> "$work/control.yaml" <<YAML
            - name: SKELA_IMAGE_PULL_SECRET
              value: $pull_secret
YAML
fi
if [ "$provider" = azure ]; then
    cat >> "$work/control.yaml" <<YAML
            - name: SKELA_BACKUP_AZURE_ACCOUNT
              value: $SKELA_BACKUP_AZURE_ACCOUNT
YAML
fi
if [ "$per_project" = 1 ]; then
    cat >> "$work/kustomization.yaml" <<YAML
  - patch: |
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: skela-control
      spec:
        template:
          spec:
            containers:
              - name: control
                env:
                  - name: SKELA_BACKUP_BUCKET
                    \$patch: delete
                  - name: SKELA_BACKUP_PER_PROJECT
                    value: "1"
YAML
fi
if [ -n "$pull_secret" ]; then
    cat >> "$work/kustomization.yaml" <<YAML
  - target: { kind: Deployment }
    patch: |
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value: [{ name: $pull_secret }]
YAML
fi
if [ -n "$tls_issuer" ]; then
    cat >> "$work/kustomization.yaml" <<YAML
  - target: { kind: Certificate }
    patch: |
      - op: replace
        path: /spec/issuerRef/name
        value: $tls_issuer
  - target: { kind: Certificate, name: skela-proxy-tls }
    patch: |
      - op: replace
        path: /spec/dnsNames
        value: [$SKELA_TLS_DNS_NAME]
  - patch: |
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: skela-control
      spec:
        template:
          spec:
            containers:
              - name: control
                env:
                  - { name: SKELA_COMPUTE_ISSUER, value: $tls_issuer }
components:
  - ../tls
YAML
fi
kubectl kustomize "$work" > "$work/install.yaml"
if [ "$mode" = render ]; then
    cat "$work/install.yaml"
    exit 0
fi
: "${SKELA_KUBE_CONTEXT:?set the exact target context for apply}"
kube=(kubectl --context "$SKELA_KUBE_CONTEXT" --request-timeout=30s)
if [ "$provider" = aws ] && [ "$SKELA_STORAGE_CLASS" = skela-gp3 ]; then
    "${kube[@]}" get csidriver ebs.csi.aws.com >/dev/null
else
    "${kube[@]}" get storageclass "$SKELA_STORAGE_CLASS" >/dev/null
fi
api_token=$("${kube[@]}" -n skela get secret skela-api -o 'jsonpath={.data.token}')
[ -n "$api_token" ] || { echo 'skela-api Secret must have a nonempty token key' >&2; exit 1; }
unset api_token
if [ -n "$pull_secret" ]; then
    "${kube[@]}" -n skela get secret "$pull_secret" >/dev/null
fi
if [ -n "$tls_issuer" ]; then
    "${kube[@]}" -n skela get issuer "$tls_issuer" >/dev/null
fi
"${kube[@]}" apply -f "$work/install.yaml"
"${kube[@]}" -n skela rollout status deployment/skela-control --timeout=180s
"${kube[@]}" -n skela rollout status deployment/skela-proxy --timeout=180s
