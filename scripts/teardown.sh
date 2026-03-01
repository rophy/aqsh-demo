#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

echo "=== Deleting Kind clusters ==="

for cluster in cluster-a cluster-b cluster-c; do
  if kind get clusters 2>/dev/null | grep -qx "$cluster"; then
    echo "Deleting $cluster..."
    kind delete cluster --name "$cluster"
  else
    echo "$cluster does not exist, skipping"
  fi
done

if [ -f "$ENV_FILE" ]; then
  rm "$ENV_FILE"
  echo "Removed $ENV_FILE"
fi

echo "=== Teardown complete ==="
