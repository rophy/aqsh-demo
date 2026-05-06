#!/bin/bash
set -e

STS_NAME="mariadb"

echo "Rolling restart: StatefulSet ${STS_NAME} in namespace ${DB_NAMESPACE}"

kubectl -n "${DB_NAMESPACE}" rollout restart statefulset "${STS_NAME}"

echo "Waiting for rollout to complete..."
kubectl -n "${DB_NAMESPACE}" rollout status statefulset "${STS_NAME}" --timeout=300s

REPLICAS=$(kubectl -n "${DB_NAMESPACE}" get statefulset "${STS_NAME}" -o jsonpath='{.status.readyReplicas}')

echo "Rollout complete!"
cat > "$AQSH_RESULT_FILE" << EOF
{
  "namespace": "${DB_NAMESPACE}",
  "statefulset": "${STS_NAME}",
  "replicas": ${REPLICAS}
}
EOF
