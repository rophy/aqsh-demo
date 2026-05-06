#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

source "$ENV_FILE"

AQSH_URL="http://${CLUSTER_DBS_IP}:30081"
FEDAUTH_URL="http://${CLUSTER_AUTH_IP}:30080"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# run_cmd: echo a command, run it, capture and display output
# Usage: run_cmd VARNAME cmd [args...]
# Sets $VARNAME to the command's stdout
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

echo "=== Test 1: kube-federated-auth health check ==="

run_cmd BODY curl -s "${FEDAUTH_URL}/health"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${FEDAUTH_URL}/health")
echo "  > HTTP $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
  pass "kube-federated-auth /health returned 200"
else
  fail "kube-federated-auth /health returned $HTTP_CODE (expected 200)"
fi

echo ""
echo "=== Test 2: Unauthenticated request to aqsh ==="

run_cmd BODY curl -s "${AQSH_URL}/health"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${AQSH_URL}/health")
echo "  > HTTP $HTTP_CODE"
if [ "$HTTP_CODE" = "401" ]; then
  pass "unauthenticated request returned 401"
else
  fail "unauthenticated request returned $HTTP_CODE (expected 401)"
fi

echo ""
echo "=== Test 3: Authenticated task submission (app-a) ==="

echo "  \$ kubectl --context kind-cluster-apps -n app-a create token test-client --duration=10m"
TOKEN=$(kubectl --context kind-cluster-apps -n app-a create token test-client --duration=10m)
echo "  > ${TOKEN:0:32}...${TOKEN: -16} (${#TOKEN} chars)"

echo "  \$ curl -s -X POST ${AQSH_URL}/tasks/hello -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' -d '{\"name\": \"World\"}'"
RESPONSE=$(curl -s -w '\n%{http_code}' \
  -X POST "${AQSH_URL}/tasks/hello" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "World"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
echo "  > HTTP $HTTP_CODE"
echo "  > $BODY"

if [ "$HTTP_CODE" = "202" ]; then
  pass "task submission returned 202"
else
  fail "task submission returned $HTTP_CODE (expected 202)"
fi

TASK_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)

if [ -z "$TASK_ID" ]; then
  fail "could not extract task ID from response"
  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "=== Test 4: Task completion (polling) ==="

MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
  RESPONSE=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${AQSH_URL}/tasks/${TASK_ID}")

  STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)

  echo "  \$ curl -s ${AQSH_URL}/tasks/${TASK_ID} -H 'Authorization: Bearer <token>'"
  echo "  > status=$STATUS"

  if [ "$STATUS" = "completed" ]; then
    echo "  > $RESPONSE" | python3 -c "import sys,json; json.dump(json.load(sys.stdin),sys.stdout,indent=2)" 2>/dev/null | sed 's/^/  > /' || echo "  > $RESPONSE"
    pass "task completed successfully"
    break
  elif [ "$STATUS" = "failed" ]; then
    echo "  > $RESPONSE"
    fail "task failed"
    break
  fi

  if [ "$i" = "$MAX_WAIT" ]; then
    fail "task did not complete within ${MAX_WAIT}s (status: $STATUS)"
  fi

  sleep 1
done

echo ""
echo "=== Test 5: Log streaming ==="

echo "  \$ curl -s ${AQSH_URL}/tasks/${TASK_ID}/logs?follow=false -H 'Authorization: Bearer <token>'"
LOGS=$(curl -s -m 5 \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: text/event-stream" \
  "${AQSH_URL}/tasks/${TASK_ID}/logs?follow=false" 2>/dev/null || true)
echo "$LOGS" | sed 's/^/  > /'

if echo "$LOGS" | grep -q "Hello, World!"; then
  pass "logs contain expected output"
else
  fail "logs missing expected output"
fi

echo ""
echo "=== Test 6: In-pod test from cluster-apps (app-a) ==="

echo "  \$ kubectl --context kind-cluster-apps -n app-a exec <test-client-pod> -- sh -c 'curl ... http://${CLUSTER_DBS_IP}:30081/tasks/hello'"

kubectl --context kind-cluster-apps -n app-a wait --for=condition=Ready pod -l app=test-client --timeout=120s >/dev/null
TEST_POD=$(kubectl --context kind-cluster-apps -n app-a get pod -l app=test-client -o jsonpath='{.items[0].metadata.name}')

IN_POD_RESPONSE=$(kubectl --context kind-cluster-apps -n app-a exec "$TEST_POD" -- \
  sh -c 'curl -s -w "\n%{http_code}" \
    -X POST "http://'"${CLUSTER_DBS_IP}"':30081/tasks/hello" \
    -H "Authorization: Bearer $(cat /var/run/secrets/tokens/token)" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"from-pod\"}"' 2>/dev/null || echo -e "\n000")

IN_POD_CODE=$(echo "$IN_POD_RESPONSE" | tail -1)
IN_POD_BODY=$(echo "$IN_POD_RESPONSE" | sed '$d')
echo "  > HTTP $IN_POD_CODE"
echo "  > $IN_POD_BODY"

if [ "$IN_POD_CODE" = "202" ]; then
  pass "in-pod request returned 202"
else
  fail "in-pod request returned $IN_POD_CODE (expected 202)"
fi

echo ""
echo "=== Test 7: Restart task (rolling restart db-1) ==="

echo "  \$ kubectl --context kind-cluster-dbs -n db-1 get statefulset mariadb (before restart)"
BEFORE_GENERATION=$(kubectl --context kind-cluster-dbs -n db-1 get statefulset mariadb -o jsonpath='{.status.observedGeneration}')
echo "  > observedGeneration=$BEFORE_GENERATION"

echo "  \$ curl -s -X POST ${AQSH_URL}/tasks/restart -H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' -d '{\"namespace\": \"db-1\"}'"
RESPONSE=$(curl -s -w '\n%{http_code}' \
  -X POST "${AQSH_URL}/tasks/restart" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"namespace": "db-1"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
echo "  > HTTP $HTTP_CODE"
echo "  > $BODY"

if [ "$HTTP_CODE" = "202" ]; then
  pass "restart task submission returned 202"
else
  fail "restart task submission returned $HTTP_CODE (expected 202)"
fi

echo ""
echo "=== Test 8: Restart task completion (polling) ==="

RESTART_TASK_ID=$(echo "$BODY" | jq -r '.id' 2>/dev/null || true)

if [ -z "$RESTART_TASK_ID" ]; then
  fail "could not extract restart task ID from response"
else
  MAX_WAIT=120
  for i in $(seq 1 $MAX_WAIT); do
    STATUS=$(curl -s \
      -H "Authorization: Bearer ${TOKEN}" \
      "${AQSH_URL}/tasks/${RESTART_TASK_ID}" | jq -r '.status' 2>/dev/null || true)

    if [ "$((i % 10))" = "0" ] || [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
      echo "  > status=$STATUS"
    fi

    if [ "$STATUS" = "completed" ]; then
      pass "restart task completed"
      break
    elif [ "$STATUS" = "failed" ]; then
      fail "restart task failed"
      break
    fi

    if [ "$i" = "$MAX_WAIT" ]; then
      fail "restart task did not complete within ${MAX_WAIT}s (status: $STATUS)"
    fi

    sleep 1
  done
fi

echo ""
echo "=== Test 9: Verify StatefulSet restarted (kubectl) ==="

echo "  \$ kubectl --context kind-cluster-dbs -n db-1 wait pod -l app.kubernetes.io/name=mariadb --for=condition=Ready"
kubectl --context kind-cluster-dbs -n db-1 wait pod -l app.kubernetes.io/name=mariadb --for=condition=Ready --timeout=120s >/dev/null

AFTER_GENERATION=$(kubectl --context kind-cluster-dbs -n db-1 get statefulset mariadb -o jsonpath='{.status.observedGeneration}')
READY=$(kubectl --context kind-cluster-dbs -n db-1 get statefulset mariadb -o jsonpath='{.status.readyReplicas}')
REPLICAS=$(kubectl --context kind-cluster-dbs -n db-1 get statefulset mariadb -o jsonpath='{.status.replicas}')
echo "  > observedGeneration=$AFTER_GENERATION (was $BEFORE_GENERATION)"
echo "  > replicas=$REPLICAS ready=$READY"

if [ "$AFTER_GENERATION" -gt "$BEFORE_GENERATION" ] 2>/dev/null; then
  pass "StatefulSet generation advanced ($BEFORE_GENERATION → $AFTER_GENERATION)"
else
  fail "StatefulSet generation did not advance (still $AFTER_GENERATION)"
fi

if [ "$READY" = "$REPLICAS" ] && [ "$READY" != "0" ]; then
  pass "all replicas ready ($READY/$REPLICAS)"
else
  fail "replicas not ready ($READY/$REPLICAS)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
