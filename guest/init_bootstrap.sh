#!/bin/sh
# Bootstrap script for Alpine Linux first boot inside the QEMU VM.
# Installs Docker, reads the API token from fw_cfg, and starts the API server.
# This file is placed at /bootstrap/init_bootstrap.sh inside the guest.

set -e

echo "=== Docker VM Bootstrap Starting ==="

# ---------------------------------------------------------------------------
# Read API token from QEMU fw_cfg
# The Android app injects it via: -fw_cfg name=opt/api_token,string=<TOKEN>
# ---------------------------------------------------------------------------
FW_CFG_TOKEN="/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw"
TOKEN_FILE="/bootstrap/token"

if [ -f "$FW_CFG_TOKEN" ]; then
    TOKEN=$(cat "$FW_CFG_TOKEN")
    echo "API token loaded from fw_cfg"
else
    echo "WARNING: fw_cfg token not found at $FW_CFG_TOKEN"
    # Fallback: use env var (useful for testing outside of QEMU)
    TOKEN="${API_TOKEN:-}"
fi

if [ -z "$TOKEN" ]; then
    echo "ERROR: No API token available. The server will reject all requests."
else
    # Write token to file so api_server.py can also find it
    echo -n "$TOKEN" > "$TOKEN_FILE"
    echo "Token written to $TOKEN_FILE"
fi

# ---------------------------------------------------------------------------
# Package setup
# ---------------------------------------------------------------------------
echo "Updating package index..."
apk update

echo "Installing Docker..."
apk add docker docker-cli

echo "Installing Python and pip..."
apk add python3 py3-pip

# ---------------------------------------------------------------------------
# Docker service
# ---------------------------------------------------------------------------
echo "Enabling Docker service..."
rc-update add docker default
service docker start

echo "Waiting for Docker to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "ERROR: Docker failed to start within 60s"
    exit 1
fi

# ---------------------------------------------------------------------------
# API server dependencies
# ---------------------------------------------------------------------------
echo "Installing API server dependencies..."
if [ -f /bootstrap/requirements.txt ]; then
    pip3 install --no-cache-dir -r /bootstrap/requirements.txt
else
    pip3 install --no-cache-dir fastapi==0.109.0 uvicorn==0.27.0 pydantic==2.5.3
fi

# ---------------------------------------------------------------------------
# OpenRC service for API server
# ---------------------------------------------------------------------------
echo "Creating API server OpenRC service..."
cat > /etc/init.d/docker-api <<'RCEOF'
#!/sbin/openrc-run

name="Docker API Server"
description="FastAPI server for Docker container management"
command="/usr/bin/python3"
command_args="/bootstrap/api_server.py"
command_background=true
pidfile="/run/docker-api.pid"
output_log="/var/log/docker-api.log"
error_log="/var/log/docker-api.log"

depend() {
    need docker
    after docker
}

start_pre() {
    checkpath --directory --mode 0755 /var/log
}
RCEOF

chmod +x /etc/init.d/docker-api
rc-update add docker-api default

# Export the token so the api_server subprocess picks it up via os.environ
export API_TOKEN="$TOKEN"
service docker-api start

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
echo "Waiting for API server to respond..."
timeout=30
while [ $timeout -gt 0 ]; do
    if wget -q -O- http://127.0.0.1:7080/health >/dev/null 2>&1; then
        echo "API server is ready"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "WARNING: API server health check timed out — check /var/log/docker-api.log"
fi

echo "=== Bootstrap Complete ==="
echo "Docker: $(docker --version)"
echo "API:    http://127.0.0.1:7080 (hostfwd → Android localhost:7080)"
