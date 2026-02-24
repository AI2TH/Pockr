#!/bin/bash
# Generate SHA-256 checksums for all assets.
# Runs inside a Docker container — no host-side shasum required.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required but not found."
    exit 1
fi

if [ ! -d "${ASSETS_DIR}" ]; then
    echo "ERROR: Assets directory not found: ${ASSETS_DIR}"
    exit 1
fi

echo "=== Generating Asset Checksums (via Docker) ==="

# Mount assets read-write so the container can write checksums.txt
docker run --rm \
    --platform linux/amd64 \
    -v "${ASSETS_DIR}:/assets" \
    alpine:3.19 \
    sh -c '
set -e
cd /assets

echo "Scanning for files..."
# Collect all files, excluding checksums.txt and .gitkeep/.DS_Store
FILES=$(find . -type f \
    ! -name "checksums.txt" \
    ! -name ".gitkeep" \
    ! -name ".DS_Store" \
    | sort)

if [ -z "$FILES" ]; then
    echo "WARNING: No asset files found."
    exit 1
fi

echo "Generating SHA-256 checksums..."
echo ""

# sha256sum writes "hash  ./path" format
# shellcheck disable=SC2086
sha256sum $FILES | tee /assets/checksums.txt

echo ""
echo "=== File Sizes ==="
# shellcheck disable=SC2086
du -h $FILES | sort -h

echo ""
SIZE_TOTAL=$(du -sh /assets | cut -f1)
echo "Total assets: $SIZE_TOTAL"

echo ""
echo "Checksums written to: /assets/checksums.txt"

# Quick check for critical files
echo ""
echo "=== Critical Files ==="
for f in \
    qemu/qemu-system-aarch64 \
    qemu/qemu-img \
    vm/base.qcow2.gz \
    bootstrap/api_server.py \
    bootstrap/init_bootstrap.sh; do
    if [ -f "/assets/$f" ]; then
        echo "  OK  $f"
    else
        echo "  MISS $f"
    fi
done
'

echo ""
echo "✅  Checksums saved to android/app/src/main/assets/checksums.txt"
