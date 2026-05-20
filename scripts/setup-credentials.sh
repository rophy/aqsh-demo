#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

# shellcheck source=/dev/null
source "$ENV_FILE"

MODE="${MODE:-single}"

echo "=== Extracting OIDC issuers ==="

get_issuer() {
  local context="kind-${1}"
  kubectl --context "$context" get --raw /.well-known/openid-configuration | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['issuer'])"
}

get_ca_cert() {
  local context="kind-${1}"
  kubectl --context "$context" config view --raw \
    -o jsonpath="{.clusters[?(@.name==\"kind-${1}\")].cluster.certificate-authority-data}" \
    | base64 -d
}

create_token() {
  local cluster="$1"
  kubectl --context "kind-${cluster}" -n db-ops create token kube-federated-auth-reader \
    --duration=168h \
    --audience=https://kubernetes.default.svc.cluster.local
}

ISSUER_REGION_A=$(get_issuer cluster-region-a)
ISSUER_APPS_MINIO=$(get_issuer cluster-apps-minio)
echo "cluster-region-a   issuer: $ISSUER_REGION_A"
echo "cluster-apps-minio issuer: $ISSUER_APPS_MINIO"

sed -i '/^ISSUER_/d' "$ENV_FILE"
cat >> "$ENV_FILE" <<EOF
ISSUER_REGION_A=${ISSUER_REGION_A}
ISSUER_APPS_MINIO=${ISSUER_APPS_MINIO}
EOF

CA_REGION_A=$(get_ca_cert cluster-region-a)
CA_APPS_MINIO=$(get_ca_cert cluster-apps-minio)
TOKEN_REGION_A=$(create_token cluster-region-a)
TOKEN_APPS_MINIO=$(create_token cluster-apps-minio)

# === Single-mode: store apps-minio credentials in region-a ===
echo "=== Storing remote credentials in cluster-region-a ==="

kubectl --context kind-cluster-region-a -n db-ops create configmap kube-federated-auth-ca-certs \
  --from-literal="apps-minio-ca.crt=${CA_APPS_MINIO}" \
  --dry-run=client -o yaml | kubectl --context kind-cluster-region-a apply -f -

kubectl --context kind-cluster-region-a -n db-ops create secret generic kube-federated-auth-tokens \
  --from-literal="apps-minio-token=${TOKEN_APPS_MINIO}" \
  --dry-run=client -o yaml | kubectl --context kind-cluster-region-a apply -f -

if [[ "$MODE" == "multi" ]]; then
  ISSUER_REGION_B=$(get_issuer cluster-region-b)
  echo "cluster-region-b   issuer: $ISSUER_REGION_B"
  echo "ISSUER_REGION_B=${ISSUER_REGION_B}" >> "$ENV_FILE"

  CA_REGION_B=$(get_ca_cert cluster-region-b)
  TOKEN_REGION_B=$(create_token cluster-region-b)

  echo "=== Storing cross-region credentials in cluster-region-a ==="
  kubectl --context kind-cluster-region-a -n db-ops create configmap kube-federated-auth-ca-certs \
    --from-literal="region-b-ca.crt=${CA_REGION_B}" \
    --from-literal="apps-minio-ca.crt=${CA_APPS_MINIO}" \
    --dry-run=client -o yaml | kubectl --context kind-cluster-region-a apply -f -

  kubectl --context kind-cluster-region-a -n db-ops create secret generic kube-federated-auth-tokens \
    --from-literal="region-b-token=${TOKEN_REGION_B}" \
    --from-literal="apps-minio-token=${TOKEN_APPS_MINIO}" \
    --dry-run=client -o yaml | kubectl --context kind-cluster-region-a apply -f -

  echo "=== Storing cross-region credentials in cluster-region-b ==="
  kubectl --context kind-cluster-region-b -n db-ops create configmap kube-federated-auth-ca-certs \
    --from-literal="region-a-ca.crt=${CA_REGION_A}" \
    --from-literal="apps-minio-ca.crt=${CA_APPS_MINIO}" \
    --dry-run=client -o yaml | kubectl --context kind-cluster-region-b apply -f -

  kubectl --context kind-cluster-region-b -n db-ops create secret generic kube-federated-auth-tokens \
    --from-literal="region-a-token=${TOKEN_REGION_A}" \
    --from-literal="apps-minio-token=${TOKEN_APPS_MINIO}" \
    --dry-run=client -o yaml | kubectl --context kind-cluster-region-b apply -f -
fi

echo "=== Credentials setup complete ==="
