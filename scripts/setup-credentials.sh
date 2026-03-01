#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

source "$ENV_FILE"

echo "=== Extracting OIDC issuers ==="

get_issuer() {
  local context="kind-${1}"
  kubectl --context "$context" get --raw /.well-known/openid-configuration | python3 -c "import sys,json; print(json.load(sys.stdin)['issuer'])"
}

ISSUER_B=$(get_issuer cluster-b)
ISSUER_C=$(get_issuer cluster-c)

echo "cluster-b issuer: $ISSUER_B"
echo "cluster-c issuer: $ISSUER_C"

# Append issuers to .env
cat >> "$ENV_FILE" <<EOF
ISSUER_B=${ISSUER_B}
ISSUER_C=${ISSUER_C}
EOF

echo "=== Extracting CA certificates ==="

get_ca_cert() {
  local context="kind-${1}"
  kubectl --context "$context" config view --raw -o jsonpath="{.clusters[?(@.name==\"kind-${1}\")].cluster.certificate-authority-data}" | base64 -d
}

CA_B=$(get_ca_cert cluster-b)
CA_C=$(get_ca_cert cluster-c)

echo "=== Creating bootstrap tokens for cluster-b and cluster-c ==="

create_token() {
  local cluster="$1"
  local context="kind-${cluster}"
  kubectl --context "$context" -n aqsh-demo create token kube-federated-auth-reader \
    --duration=168h \
    --audience=https://kubernetes.default.svc.cluster.local
}

TOKEN_B=$(create_token cluster-b)
TOKEN_C=$(create_token cluster-c)

echo "=== Storing CA certs as ConfigMap in cluster-a ==="

kubectl --context kind-cluster-a -n aqsh-demo create configmap kube-federated-auth-ca-certs \
  --from-literal="cluster-b-ca.crt=${CA_B}" \
  --from-literal="cluster-c-ca.crt=${CA_C}" \
  --dry-run=client -o yaml | kubectl --context kind-cluster-a apply -f -

echo "=== Storing tokens as Secret in cluster-a ==="

kubectl --context kind-cluster-a -n aqsh-demo create secret generic kube-federated-auth-tokens \
  --from-literal="cluster-b-token=${TOKEN_B}" \
  --from-literal="cluster-c-token=${TOKEN_C}" \
  --dry-run=client -o yaml | kubectl --context kind-cluster-a apply -f -

echo "=== Credentials setup complete ==="
