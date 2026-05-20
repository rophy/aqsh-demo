#!/usr/bin/env bash
# mariadb-failover.sh — Promote region-b MariaDB replicas to primary
#
# Use when region-a is unavailable. Stops replication on region-b and
# promotes it to writable primary. Run setup-replication.sh after
# region-a recovers to re-establish replication in reverse.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

# shellcheck source=/dev/null
source "$ENV_FILE"

NAMESPACES=(mariadb-1 mariadb-2 mariadb-3)

echo "=== MariaDB failover: promoting region-b to primary ==="

for ns in "${NAMESPACES[@]}"; do
  echo "--- Promoting ${ns} in region-b ---"

  ROOT_PASS=$(kubectl --context kind-cluster-region-b -n "$ns" \
    get secret mariadb -o jsonpath='{.data.password}' | base64 -d)

  kubectl --context kind-cluster-region-b -n "$ns" exec mariadb-0 -- \
    mariadb -uroot -p"${ROOT_PASS}" -e "
      STOP SLAVE;
      RESET SLAVE ALL;
      SET GLOBAL read_only = OFF;
    "

  echo "  ${ns}: region-b is now primary (read_only=OFF)"
done

echo ""
echo "=== Failover complete ==="
echo "  Region-B MariaDB instances are now writable primaries."
echo "  Re-run scripts/setup-replication.sh once region-a recovers."
