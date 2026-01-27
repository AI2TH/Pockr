#!/bin/sh
# Bootstrap script for Alpine Linux first boot
# This runs inside the guest VM to set up Docker and the API server

set -e

echo "=== Docker VM Bootstrap Starting ==="

# Update package index
echo "Updating package index..."
apk update

# Install Docker
echo "Installing Docker..."
apk add docker docker-cli docker-compose

# Install Python and pip
echo "Installing Python..."
apk add python3 py3-pip

# Enable and start Docker service
echo "Enabling Docker service..."
rc-update add docker default
service docker start

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
timeout=30
while [ $timeout -gt 0 ]; do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "ERROR: Docker failed to start"
    exit 1
fi

# Create bootstrap directory if it doesn't exist
mkdir -p /bootstrap

# Install API server dependencies
echo "Installing API server dependencies..."
if [ -f /bootstrap/requirements.txt ]; then
    pip3 install --no-cache-dir -r /bootstrap/requirements.txt
else
    pip3 install --no-cache-dir fastapi==0.109.0 uvicorn==0.27.0 pydantic==2.5.3
fi

# Create systemd/OpenRC service for API server
echo "Creating API server service..."
cat > /etc/init.d/docker-api <<'EOF'
#!/sbin/openrc-run

name="Docker API Server"
description="FastAPI server for Docker container management"
command="/usr/bin/python3"
command_args="/bootstrap/api_server.py"
command_background=true
pidfile="/run/docker-api.pid"

depend() {
    need docker
    after docker
}

start_pre() {
    checkpath --directory --mode 0755 /var/log
}
EOF

chmod +x /etc/init.d/docker-api

# Enable and start API server
echo "Starting API server..."
rc-update add docker-api default
service docker-api start

# Wait for API server to be ready
echo "Waiting for API server..."
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
    echo "WARNING: API server health check failed, but continuing..."
fi

echo "=== Bootstrap Complete ==="
echo "Docker version: $(docker --version)"
echo "API server should be accessible at http://127.0.0.1:7080"
echo "Check health: wget -O- http://127.0.0.1:7080/health"
