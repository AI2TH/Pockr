#!/bin/bash
# Copy bootstrap scripts from guest/ into android assets.
# All file operations run inside a Docker container.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUEST_DIR="${PROJECT_ROOT}/guest"
ASSETS_BOOTSTRAP="${PROJECT_ROOT}/android/app/src/main/assets/bootstrap"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required but not found."
    exit 1
fi

echo "=== Copying Bootstrap Scripts (via Docker) ==="
mkdir -p "${ASSETS_BOOTSTRAP}"

docker run --rm \
    --platform linux/amd64 \
    -v "${GUEST_DIR}:/src:ro" \
    -v "${ASSETS_BOOTSTRAP}:/dst" \
    alpine:3.19 \
    sh -c '
set -e
for f in api_server.py requirements.txt init_bootstrap.sh; do
    if [ -f "/src/$f" ]; then
        cp "/src/$f" "/dst/$f"
        chmod +x "/dst/$f"
        echo "  Copied: $f ($(wc -c < /dst/$f) bytes)"
    else
        echo "  WARNING: $f not found in /src — skipping"
    fi
done

echo ""
echo "Files in /dst:"
ls -lh /dst/
'

echo ""
echo "✅  Bootstrap scripts copied to android/app/src/main/assets/bootstrap/"
