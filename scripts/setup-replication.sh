#!/usr/bin/env bash
# setup-replication.sh — Configure cross-region DB replication (multi mode only)
#
# MariaDB: Sets up async binlog replication (region-a primary → region-b replica)
# MongoDB: Adds region-b members to each replica set initiated in region-a
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

# shellcheck source=/dev/null
source "$ENV_FILE"

echo "=== Setting up cross-region replication ==="

# ─────────────────────────────────────────────
# MariaDB async replication
# region-a is primary; region-b connects inbound via region-a's nginx TCP proxy
# ─────────────────────────────────────────────
setup_mariadb_replication() {
  local ns="$1"          # e.g. mariadb-1
  local port="$2"        # stream proxy NodePort on region-a nginx

  echo "--- MariaDB replication: ${ns} ---"

  # Read root password from the secret in region-a
  local ROOT_PASS
  ROOT_PASS=$(kubectl --context kind-cluster-region-a -n "$ns" \
    get secret mariadb -o jsonpath='{.data.password}' | base64 -d)

  local REPL_USER="${MARIADB_REPLICATION_USER:-repl}"
  local REPL_PASS="${MARIADB_REPLICATION_PASSWORD:-replpass}"

  # Create replication user on region-a primary
  kubectl --context kind-cluster-region-a -n "$ns" exec mariadb-0 -- \
    mariadb -uroot -p"${ROOT_PASS}" -e "
      CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED BY '${REPL_PASS}';
      GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';
      FLUSH PRIVILEGES;
    "

  # Get binlog position from region-a primary
  local BINLOG_FILE BINLOG_POS
  BINLOG_FILE=$(kubectl --context kind-cluster-region-a -n "$ns" exec mariadb-0 -- \
    mariadb -uroot -p"${ROOT_PASS}" -e "SHOW MASTER STATUS\G" | awk '/File:/ {print $2}')
  BINLOG_POS=$(kubectl --context kind-cluster-region-a -n "$ns" exec mariadb-0 -- \
    mariadb -uroot -p"${ROOT_PASS}" -e "SHOW MASTER STATUS\G" | awk '/Position:/ {print $2}')

  echo "  Primary binlog: ${BINLOG_FILE}:${BINLOG_POS}"

  # Read root password from region-b
  local ROOT_PASS_B
  ROOT_PASS_B=$(kubectl --context kind-cluster-region-b -n "$ns" \
    get secret mariadb -o jsonpath='{.data.password}' | base64 -d)

  # Configure region-b as replica pointing to region-a via nginx TCP proxy
  kubectl --context kind-cluster-region-b -n "$ns" exec mariadb-0 -- \
    mariadb -uroot -p"${ROOT_PASS_B}" -e "
      STOP SLAVE;
      CHANGE MASTER TO
        MASTER_HOST='${REGION_A_IP}',
        MASTER_PORT=${port},
        MASTER_USER='${REPL_USER}',
        MASTER_PASSWORD='${REPL_PASS}',
        MASTER_LOG_FILE='${BINLOG_FILE}',
        MASTER_LOG_POS=${BINLOG_POS};
      START SLAVE;
    "

  echo "  Replica started for ${ns}"
}

# ─────────────────────────────────────────────
# MongoDB RS: add region-b member to each RS
# region-a already has rs.initiate() with 1 member
# ─────────────────────────────────────────────
setup_mongo_replication() {
  local ns="$1"      # e.g. mongo-1
  local port="$2"    # stream proxy NodePort on region-b nginx (inbound to region-b mongo)

  echo "--- MongoDB RS expansion: ${ns} ---"

  local RS_NAME="rs-${ns}"
  local ROOT_USER ROOT_PASS

  ROOT_USER=$(kubectl --context kind-cluster-region-a -n "$ns" \
    get secret mongodb-credentials -o jsonpath='{.data.MONGO_ROOT_USER}' | base64 -d)
  ROOT_PASS=$(kubectl --context kind-cluster-region-a -n "$ns" \
    get secret mongodb-credentials -o jsonpath='{.data.MONGO_ROOT_PASS}' | base64 -d)

  # Add region-b's mongo as a secondary via region-b's nginx TCP proxy
  # The host that region-a's RS uses to connect to region-b member:
  #   region-b nginx NodePort routes port $port → mongodb.mongo-X:27017
  kubectl --context kind-cluster-region-a -n "$ns" exec mongodb-0 -- \
    mongosh --quiet --norc \
    -u "$ROOT_USER" -p "$ROOT_PASS" --authenticationDatabase admin \
    --eval "rs.add({host: '${REGION_B_IP}:${port}', priority: 1, votes: 1})" \
    2>/dev/null || echo "  rs.add already applied or not primary, skipping"

  echo "  RS member added: ${REGION_B_IP}:${port}"
}

# Stream proxy port assignments (nginx NodePort on each region):
#   mongo-1 → 30092, mongo-2 → 30094, mongo-3 → 30096
#   mariadb-1 → 30093, mariadb-2 → 30095, mariadb-3 → 30097

setup_mariadb_replication mariadb-1 30093
setup_mariadb_replication mariadb-2 30095
setup_mariadb_replication mariadb-3 30097

setup_mongo_replication mongo-1 30092
setup_mongo_replication mongo-2 30094
setup_mongo_replication mongo-3 30096

echo "=== Cross-region replication setup complete ==="
