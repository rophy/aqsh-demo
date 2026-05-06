#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

source "$ENV_FILE"
export CLUSTER_AUTH_IP CLUSTER_DBS_IP CLUSTER_APPS_IP

echo "=== Step 1: Deploy namespaces and RBAC ==="

kubectl --context kind-cluster-auth apply -f "${ROOT_DIR}/k8s/cluster-auth/namespace.yaml"

kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/namespace.yaml"
kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/federated-auth-rbac.yaml"
kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/aqsh-rbac.yaml"
kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/aqsh-db-rbac.yaml"

kubectl --context kind-cluster-apps apply -f "${ROOT_DIR}/k8s/cluster-apps/namespace.yaml"
kubectl --context kind-cluster-apps apply -f "${ROOT_DIR}/k8s/cluster-apps/federated-auth-rbac.yaml"

echo "=== Step 2: Bootstrap credentials ==="

"${SCRIPT_DIR}/setup-credentials.sh"

# Re-source to pick up ISSUER_DBS and ISSUER_APPS added by setup-credentials.sh
source "$ENV_FILE"
export ISSUER_DBS ISSUER_APPS

echo "=== Step 3: Deploy cluster-auth (kube-federated-auth) ==="

kubectl --context kind-cluster-auth apply -f "${ROOT_DIR}/k8s/cluster-auth/rbac.yaml"

envsubst < "${ROOT_DIR}/k8s/cluster-auth/configmap.yaml.tpl" | kubectl --context kind-cluster-auth apply -f -

kubectl --context kind-cluster-auth apply -f "${ROOT_DIR}/k8s/cluster-auth/deployment.yaml"
kubectl --context kind-cluster-auth apply -f "${ROOT_DIR}/k8s/cluster-auth/service.yaml"

echo "Waiting for kube-federated-auth to be ready..."
kubectl --context kind-cluster-auth -n db-ops rollout status deployment/kube-federated-auth --timeout=120s

echo "=== Step 4: Deploy mariadb-operator ==="

helm repo add mariadb-operator https://helm.mariadb.com/mariadb-operator 2>/dev/null || true
helm repo update mariadb-operator

helm upgrade --install mariadb-operator-crds mariadb-operator/mariadb-operator-crds \
  --kube-context kind-cluster-dbs \
  --wait

helm upgrade --install mariadb-operator mariadb-operator/mariadb-operator \
  --kube-context kind-cluster-dbs \
  --namespace db-ops \
  --wait

echo "=== Step 5: Deploy MariaDB instances ==="

kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/mariadb-db-1.yaml"
kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/mariadb-db-2.yaml"
kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/mariadb-db-3.yaml"

echo "Waiting for MariaDB instances to be ready..."
kubectl --context kind-cluster-dbs -n db-1 wait --for=condition=Ready mariadb/mariadb --timeout=180s
kubectl --context kind-cluster-dbs -n db-2 wait --for=condition=Ready mariadb/mariadb --timeout=180s
kubectl --context kind-cluster-dbs -n db-3 wait --for=condition=Ready mariadb/mariadb --timeout=180s

echo "=== Step 6: Build and load aqsh-tasks image ==="

skaffold build --filename="${ROOT_DIR}/skaffold.yaml" --tag=latest --quiet
kind load docker-image aqsh-tasks:latest --name cluster-dbs

echo "=== Step 7: Deploy cluster-dbs (aqsh + kube-auth-proxy + Redis) ==="

kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/redis.yaml"

envsubst < "${ROOT_DIR}/k8s/cluster-dbs/aqsh-deployment.yaml.tpl" | kubectl --context kind-cluster-dbs apply -f -

kubectl --context kind-cluster-dbs apply -f "${ROOT_DIR}/k8s/cluster-dbs/aqsh-service.yaml"

echo "Waiting for Redis to be ready..."
kubectl --context kind-cluster-dbs -n db-ops rollout status deployment/redis --timeout=60s

echo "Waiting for aqsh to be ready..."
kubectl --context kind-cluster-dbs -n db-ops rollout status deployment/aqsh --timeout=120s

echo "=== Step 8: Deploy cluster-apps (test-client) ==="

kubectl --context kind-cluster-apps apply -f "${ROOT_DIR}/k8s/cluster-apps/test-client.yaml"

echo "Waiting for test-client to be ready..."
kubectl --context kind-cluster-apps -n app-a rollout status deployment/test-client --timeout=60s
kubectl --context kind-cluster-apps -n app-b rollout status deployment/test-client --timeout=60s

echo "=== Deployment complete ==="
