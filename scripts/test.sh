#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

# shellcheck source=/dev/null
source "$ENV_FILE"

MARIADB_AQSH_URL="http://${REGION_A_IP}:30080/mariadb"
MONGODB_AQSH_URL="http://${REGION_A_IP}:30080/mongodb"
FEDAUTH_URL="http://${REGION_A_IP}:30081"
CLUSTER_DBS_IP="${REGION_A_IP}"
PASS=0
FAIL=0
export MARIADB_AQSH_URL MONGODB_AQSH_URL FEDAUTH_URL CLUSTER_DBS_IP

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_cmd() {
  local varname="$1"; shift
  echo "  \$ $*"
  local output
  output=$("$@" 2>&1) || true
  if [ -n "$output" ]; then
    echo "$output" | sed 's/^/  > /'
  fi
  eval "$varname=\$output"
}

# Run all test suites (TOKEN is set by tests/common/test.sh and reused below)
TOKEN=""
export TOKEN

# Disable -e so that individual command failures inside suites are recorded
# via fail() and do not abort the whole run.
set +e
# shellcheck source=../tests/common/test.sh
source "${ROOT_DIR}/tests/common/test.sh"
# shellcheck source=../tests/mariadb/test.sh
source "${ROOT_DIR}/tests/mariadb/test.sh"
# shellcheck source=../tests/mongodb/test.sh
source "${ROOT_DIR}/tests/mongodb/test.sh"
set -e

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
