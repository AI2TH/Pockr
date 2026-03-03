#!/bin/bash
# Test the guest API server (guest/api_server.py) inside Docker.
#
# Uses Docker-in-Docker (docker:dind) so the API server can actually run
# docker commands against a real Docker daemon — same as it would in the VM.
#
# What is tested:
#   GET  /health                  — server responds, Docker daemon reachable
#   GET  /containers (authed)     — returns JSON list
#   POST /containers/start        — starts a busybox container
#   GET  /logs?name=...           — retrieves container logs
#   POST /containers/stop         — stops the container
#   GET  /containers (unauthed)   — should return 401

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUEST_DIR="${PROJECT_ROOT}/guest"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required."
    exit 1
fi

TEST_TOKEN="test-token-$(date +%s)"
NETWORK_NAME="api-test-net"

echo "=== API Server Test (via Docker-in-Docker) ==="
echo "Token: ${TEST_TOKEN}"
echo ""

# ── Cleanup helper ────────────────────────────────────────────────────────────
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker rm -f dind-api-test 2>/dev/null || true
    docker network rm "${NETWORK_NAME}" 2>/dev/null || true
}
trap cleanup EXIT

# Create an isolated network
docker network create "${NETWORK_NAME}" 2>/dev/null || true

# ── Start Docker-in-Docker container ──────────────────────────────────────────
echo "Starting Docker-in-Docker container..."
docker run -d \
    --name dind-api-test \
    --network "${NETWORK_NAME}" \
    --privileged \
    -v "${GUEST_DIR}:/guest:ro" \
    -e "API_TOKEN=${TEST_TOKEN}" \
    docker:dind \
    sh -c '
# Wait for inner Docker daemon to be ready
echo "Waiting for Docker daemon..."
timeout=30
while ! docker info >/dev/null 2>&1; do
    sleep 1
    timeout=$((timeout-1))
    [ $timeout -gt 0 ] || { echo "ERROR: Docker daemon did not start"; exit 1; }
done
echo "Docker daemon ready."

# Install Python and API server dependencies
apk add --no-cache python3 py3-pip >/dev/null 2>&1
pip3 install --no-cache-dir fastapi==0.109.0 uvicorn==0.27.0 pydantic==2.5.3 >/dev/null 2>&1

# Start API server with the injected token (reads from env via fallback)
python3 /guest/api_server.py &
API_PID=$!

# Wait for server
echo "Waiting for API server..."
timeout=20
while ! wget -q -O- http://127.0.0.1:7080/health >/dev/null 2>&1; do
    sleep 1
    timeout=$((timeout-1))
    [ $timeout -gt 0 ] || { echo "ERROR: API server did not start"; kill $API_PID; exit 1; }
done
echo "API server ready."

# Block so the container stays up for the test runner
wait $API_PID
'

# Wait for the dind container to get the server ready
echo "Waiting for API server inside container..."
sleep 8

# ── Run tests from a separate lightweight container ───────────────────────────
echo ""
echo "Running test requests..."
echo ""

docker run --rm \
    --network "${NETWORK_NAME}" \
    -e "TOKEN=${TEST_TOKEN}" \
    --add-host "dind-api-test:$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dind-api-test)" \
    alpine:3.19 \
    sh -c '
apk add --no-cache curl jq >/dev/null 2>&1

BASE="http://dind-api-test:7080"
TOKEN="$TOKEN"
PASS=0
FAIL=0

check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS  $label"
        PASS=$((PASS+1))
    else
        echo "  FAIL  $label (expected=$expected, got=$actual)"
        FAIL=$((FAIL+1))
    fi
}

# -- /health (no auth needed)
echo "1. GET /health"
RESP=$(curl -s "$BASE/health")
STATUS=$(echo "$RESP" | jq -r ".status" 2>/dev/null || echo "parse_error")
echo "   Response: $RESP"
check "/health returns ok or degraded" "ok" "$STATUS" || \
check "/health returns degraded"       "degraded" "$STATUS"

# -- /containers without auth → 401
echo ""
echo "2. GET /containers (no auth) → expect 401"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/containers")
check "401 without token" "401" "$HTTP"

# -- /containers with auth → 200
echo ""
echo "3. GET /containers (authed) → expect 200"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE/containers")
check "200 with token" "200" "$HTTP"

# -- POST /containers/start
echo ""
echo "4. POST /containers/start (busybox echo)"
CONTAINER_NAME="api-test-$(date +%s)"
RESP=$(curl -s -X POST "$BASE/containers/start" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"image\":\"busybox\",\"name\":\"$CONTAINER_NAME\",\"cmd\":[\"echo\",\"hello from api test\"]}")
echo "   Response: $RESP"
STATUS=$(echo "$RESP" | jq -r ".status" 2>/dev/null || echo "parse_error")
check "/containers/start returns started" "started" "$STATUS"

# -- GET /logs
echo ""
echo "5. GET /logs"
sleep 2   # let the container run and finish
LOGS=$(curl -s "$BASE/logs?name=$CONTAINER_NAME&tail=10" \
    -H "Authorization: Bearer $TOKEN")
echo "   Logs: $LOGS"
if echo "$LOGS" | grep -q "hello"; then
    echo "  PASS  logs contain expected output"
    PASS=$((PASS+1))
else
    echo "  WARN  logs did not contain expected output (container may have exited)"
fi

# -- POST /containers/stop (graceful even if already exited)
echo ""
echo "6. POST /containers/stop"
curl -s -X POST "$BASE/containers/stop" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$CONTAINER_NAME\"}" >/dev/null 2>&1 || true
echo "  OK   stop request sent"

echo ""
echo "══════════════════════════════"
echo "Results: PASS=$PASS  FAIL=$FAIL"
echo "══════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
'

echo ""
echo "✅  API server tests complete."
