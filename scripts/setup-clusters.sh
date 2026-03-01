#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

CLUSTERS=(cluster-a cluster-b cluster-c)

echo "=== Creating Kind clusters ==="

for cluster in "${CLUSTERS[@]}"; do
  if kind get clusters 2>/dev/null | grep -qx "$cluster"; then
    echo "Cluster $cluster already exists, skipping"
  else
    echo "Creating $cluster..."
    kind create cluster --name "$cluster" --wait 60s
  fi
done

echo "=== Extracting Docker IPs ==="

get_node_ip() {
  docker inspect "${1}-control-plane" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
}

CLUSTER_A_IP=$(get_node_ip cluster-a)
CLUSTER_B_IP=$(get_node_ip cluster-b)
CLUSTER_C_IP=$(get_node_ip cluster-c)

echo "cluster-a: $CLUSTER_A_IP"
echo "cluster-b: $CLUSTER_B_IP"
echo "cluster-c: $CLUSTER_C_IP"

cat > "$ENV_FILE" <<EOF
CLUSTER_A_IP=${CLUSTER_A_IP}
CLUSTER_B_IP=${CLUSTER_B_IP}
CLUSTER_C_IP=${CLUSTER_C_IP}
EOF

echo "=== Wrote $ENV_FILE ==="
