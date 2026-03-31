#!/bin/sh
# Bootstrap: runs on first boot inside the QEMU VM.
# Docker and Python are pre-installed in the base image.
# This script loads kernel modules, waits for Docker, then starts the API server.

echo "=== Docker VM Bootstrap Starting ==="

# ---------------------------------------------------------------------------
# Load kernel modules required by Docker (if not already loaded by OpenRC)
# These provide bridge networking, iptables NAT, and cgroup support.
# ---------------------------------------------------------------------------
echo "Loading kernel modules..."
for mod in bridge br_netfilter nf_tables nf_nat nf_conntrack qemu_fw_cfg; do
    modprobe "$mod" 2>/dev/null && echo "  loaded: $mod" || echo "  skip: $mod (already loaded or unavailable)"
done

# Enable bridge netfilter (required for Docker iptables rules on bridged traffic)
if [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables
fi

# Ensure cgroup2 is mounted (Docker needs it for resource isolation)
if ! mountpoint -q /sys/fs/cgroup; then
    mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Read API token from kernel cmdline.
# Android app injects it via: -append "... api_token=<UUID>"
# ---------------------------------------------------------------------------
TOKEN_FILE="/bootstrap/token"

TOKEN=$(tr ' ' '\n' < /proc/cmdline | grep '^api_token=' | cut -d= -f2-)
if [ -n "$TOKEN" ]; then
    echo -n "$TOKEN" > "$TOKEN_FILE"
    echo "Token loaded from kernel cmdline"
else
    echo "WARNING: api_token not found in kernel cmdline"
    # Fallback: try fw_cfg
    FW_CFG="/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw"
    if [ -f "$FW_CFG" ]; then
        TOKEN=$(cat "$FW_CFG")
        echo -n "$TOKEN" > "$TOKEN_FILE"
        echo "Token loaded from fw_cfg"
    elif [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE")
        echo "Using persisted token from $TOKEN_FILE"
    fi
fi

export API_TOKEN="$TOKEN"

# ---------------------------------------------------------------------------
# Wait for Docker daemon (started by OpenRC docker service)
# With virtio-rng providing entropy, Docker starts much faster (~10-20s).
# ---------------------------------------------------------------------------
echo "Waiting for Docker daemon..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready (waited $((60 - timeout))s)"
        break
    fi
    # Print progress every 15s
    if [ $((timeout % 15)) -eq 0 ] && [ $timeout -lt 60 ]; then
        echo "--- still waiting (t=$((60 - timeout))s) ---"
        tail -5 /var/log/docker.log 2>/dev/null || true
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "ERROR: Docker did not become ready in 60s"
    echo "=== final dockerd log ==="
    cat /var/log/docker.log 2>/dev/null | tail -40 || true
    echo "=== docker info ==="
    docker info 2>&1 || true
    exit 1
fi

echo "Docker: $(docker --version)"

# Verify Docker networking works
echo "=== Docker network check ==="
docker network ls 2>/dev/null || echo "(network ls failed)"

# ---------------------------------------------------------------------------
# Start API server
# ---------------------------------------------------------------------------
echo "Starting API server on 0.0.0.0:7080..."
mkdir -p /var/log
API_TOKEN="$TOKEN" nohup /usr/bin/python3 /bootstrap/api_server.py \
    > /var/log/docker-api.log 2>&1 &
echo $! > /var/run/docker-api.pid
echo "API server PID: $!"

# ---------------------------------------------------------------------------
# Wait for API server to respond
# ---------------------------------------------------------------------------
echo "Waiting for API server..."
timeout=30
while [ $timeout -gt 0 ]; do
    if wget -q -O- http://127.0.0.1:7080/health >/dev/null 2>&1; then
        echo "API server is ready at http://127.0.0.1:7080"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "WARNING: API server health check timed out"
    cat /var/log/docker-api.log 2>/dev/null | tail -20 || true
fi

echo "=== Bootstrap Complete ==="
