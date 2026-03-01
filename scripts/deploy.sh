#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

source "$ENV_FILE"
export CLUSTER_A_IP CLUSTER_B_IP CLUSTER_C_IP

echo "=== Step 1: Deploy namespaces and RBAC ==="

kubectl --context kind-cluster-a apply -f "${ROOT_DIR}/k8s/cluster-a/namespace.yaml"

kubectl --context kind-cluster-b apply -f "${ROOT_DIR}/k8s/cluster-b/namespace.yaml"
kubectl --context kind-cluster-b apply -f "${ROOT_DIR}/k8s/cluster-b/federated-auth-rbac.yaml"
kubectl --context kind-cluster-b apply -f "${ROOT_DIR}/k8s/cluster-b/aqsh-rbac.yaml"

kubectl --context kind-cluster-c apply -f "${ROOT_DIR}/k8s/cluster-c/namespace.yaml"
kubectl --context kind-cluster-c apply -f "${ROOT_DIR}/k8s/cluster-c/federated-auth-rbac.yaml"

echo "=== Step 2: Bootstrap credentials ==="

"${SCRIPT_DIR}/setup-credentials.sh"

# Re-source to pick up ISSUER_B and ISSUER_C added by setup-credentials.sh
source "$ENV_FILE"
export ISSUER_B ISSUER_C

echo "=== Step 3: Deploy cluster-a (kube-federated-auth) ==="

kubectl --context kind-cluster-a apply -f "${ROOT_DIR}/k8s/cluster-a/rbac.yaml"

# Process configmap template
envsubst < "${ROOT_DIR}/k8s/cluster-a/configmap.yaml.tpl" | kubectl --context kind-cluster-a apply -f -

kubectl --context kind-cluster-a apply -f "${ROOT_DIR}/k8s/cluster-a/deployment.yaml"
kubectl --context kind-cluster-a apply -f "${ROOT_DIR}/k8s/cluster-a/service.yaml"

echo "Waiting for kube-federated-auth to be ready..."
kubectl --context kind-cluster-a -n aqsh-demo rollout status deployment/kube-federated-auth --timeout=120s

echo "=== Step 4: Deploy cluster-b (aqsh + kube-auth-proxy + Redis) ==="

kubectl --context kind-cluster-b apply -f "${ROOT_DIR}/k8s/cluster-b/redis.yaml"
kubectl --context kind-cluster-b apply -f "${ROOT_DIR}/k8s/cluster-b/aqsh-configmap.yaml"

# Process deployment template
envsubst < "${ROOT_DIR}/k8s/cluster-b/aqsh-deployment.yaml.tpl" | kubectl --context kind-cluster-b apply -f -

kubectl --context kind-cluster-b apply -f "${ROOT_DIR}/k8s/cluster-b/aqsh-service.yaml"

echo "Waiting for Redis to be ready..."
kubectl --context kind-cluster-b -n aqsh-demo rollout status deployment/redis --timeout=60s

echo "Waiting for aqsh to be ready..."
kubectl --context kind-cluster-b -n aqsh-demo rollout status deployment/aqsh --timeout=120s

echo "=== Step 5: Deploy cluster-c (test-client) ==="

kubectl --context kind-cluster-c apply -f "${ROOT_DIR}/k8s/cluster-c/test-client.yaml"

echo "Waiting for test-client to be ready..."
kubectl --context kind-cluster-c -n aqsh-demo rollout status deployment/test-client --timeout=60s

echo "=== Deployment complete ==="
