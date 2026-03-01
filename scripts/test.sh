#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

source "$ENV_FILE"

AQSH_URL="http://${CLUSTER_B_IP}:30081"
FEDAUTH_URL="http://${CLUSTER_A_IP}:30080"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Test 1: kube-federated-auth health check ==="

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${FEDAUTH_URL}/health")
if [ "$HTTP_CODE" = "200" ]; then
  pass "kube-federated-auth /health returned 200"
else
  fail "kube-federated-auth /health returned $HTTP_CODE (expected 200)"
fi

echo "=== Test 2: Unauthenticated request to aqsh ==="

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${AQSH_URL}/health")
if [ "$HTTP_CODE" = "401" ]; then
  pass "unauthenticated request returned 401"
else
  fail "unauthenticated request returned $HTTP_CODE (expected 401)"
fi

echo "=== Test 3: Authenticated task submission ==="

# Get a fresh token from the test-client SA in cluster-c
TOKEN=$(kubectl --context kind-cluster-c -n aqsh-demo create token test-client --duration=10m)

RESPONSE=$(curl -s -w '\n%{http_code}' \
  -X POST "${AQSH_URL}/tasks/hello" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "World"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "202" ]; then
  pass "task submission returned 202"
else
  fail "task submission returned $HTTP_CODE (expected 202)"
  echo "  Response: $BODY"
fi

TASK_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)

if [ -z "$TASK_ID" ]; then
  fail "could not extract task ID from response"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo "  Task ID: $TASK_ID"

echo "=== Test 4: Task completion ==="

MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
  RESPONSE=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${AQSH_URL}/tasks/${TASK_ID}")

  STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)

  if [ "$STATUS" = "completed" ]; then
    pass "task completed successfully"
    break
  elif [ "$STATUS" = "failed" ]; then
    fail "task failed"
    echo "  Response: $RESPONSE"
    break
  fi

  if [ "$i" = "$MAX_WAIT" ]; then
    fail "task did not complete within ${MAX_WAIT}s (status: $STATUS)"
  fi

  sleep 1
done

echo "=== Test 5: Log streaming ==="

LOGS=$(curl -s -m 5 \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: text/event-stream" \
  "${AQSH_URL}/tasks/${TASK_ID}/logs?follow=false" 2>/dev/null || true)

if echo "$LOGS" | grep -q "Hello, World!"; then
  pass "logs contain expected output"
else
  fail "logs missing expected output"
  echo "  Logs: $LOGS"
fi

echo "=== Test 6: In-pod test from cluster-c ==="

TEST_POD=$(kubectl --context kind-cluster-c -n aqsh-demo get pod -l app=test-client -o jsonpath='{.items[0].metadata.name}')

IN_POD_CODE=$(kubectl --context kind-cluster-c -n aqsh-demo exec "$TEST_POD" -- \
  sh -c 'curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://'"${CLUSTER_B_IP}"':30081/tasks/hello" \
    -H "Authorization: Bearer $(cat /var/run/secrets/tokens/token)" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"from-pod\"}"' 2>/dev/null || echo "000")

if [ "$IN_POD_CODE" = "202" ]; then
  pass "in-pod request returned 202"
else
  fail "in-pod request returned $IN_POD_CODE (expected 202)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
