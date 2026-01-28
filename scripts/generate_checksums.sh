#!/bin/bash
# Generate SHA-256 checksums for all assets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets"
CHECKSUM_FILE="${ASSETS_DIR}/checksums.txt"

echo "=== Generating Asset Checksums ==="
echo ""

if [ ! -d "${ASSETS_DIR}" ]; then
    echo "ERROR: Assets directory not found: ${ASSETS_DIR}"
    exit 1
fi

# Find all files in assets
cd "${ASSETS_DIR}"

echo "Scanning for asset files..."
FILES=$(find . -type f ! -name "checksums.txt" ! -name ".DS_Store")

if [ -z "${FILES}" ]; then
    echo "WARNING: No asset files found!"
    echo ""
    echo "Expected assets:"
    echo "  - qemu/qemu-system-aarch64"
    echo "  - qemu/qemu-img"
    echo "  - vm/base.qcow2.gz"
    echo "  - bootstrap/api_server.py"
    echo "  - bootstrap/init_bootstrap.sh"
    echo "  - bootstrap/requirements.txt"
    exit 1
fi

# Generate checksums
echo "Generating SHA-256 checksums..."
echo ""

shasum -a 256 ${FILES} > "${CHECKSUM_FILE}"

# Display results
echo "=== Asset Checksums ==="
echo ""
cat "${CHECKSUM_FILE}"
echo ""

# Calculate total size
TOTAL_SIZE=$(du -sh . | awk '{print $1}')
echo "Total assets size: ${TOTAL_SIZE}"
echo ""

# Show individual file sizes
echo "=== Individual File Sizes ==="
echo ""
du -h ${FILES} | sort -h

echo ""
echo "✅ Checksums saved to: ${CHECKSUM_FILE}"
echo ""

# Verify critical files
echo "=== Critical Files Check ==="
echo ""

QEMU_AARCH64="${ASSETS_DIR}/qemu/qemu-system-aarch64"
QEMU_IMG="${ASSETS_DIR}/qemu/qemu-img"
BASE_IMAGE="${ASSETS_DIR}/vm/base.qcow2.gz"
API_SERVER="${ASSETS_DIR}/bootstrap/api_server.py"
BOOTSTRAP="${ASSETS_DIR}/bootstrap/init_bootstrap.sh"

check_file() {
    local file=$1
    local name=$2

    if [ -f "${file}" ]; then
        local size=$(ls -lh "${file}" | awk '{print $5}')
        echo "✅ ${name}: ${size}"
    else
        echo "❌ ${name}: MISSING"
    fi
}

check_file "${QEMU_AARCH64}" "qemu-system-aarch64"
check_file "${QEMU_IMG}" "qemu-img"
check_file "${BASE_IMAGE}" "base.qcow2.gz"
check_file "${API_SERVER}" "api_server.py"
check_file "${BOOTSTRAP}" "init_bootstrap.sh"

echo ""

# Check if all critical files exist
if [ -f "${QEMU_AARCH64}" ] && [ -f "${QEMU_IMG}" ] && [ -f "${BASE_IMAGE}" ] && \
   [ -f "${API_SERVER}" ] && [ -f "${BOOTSTRAP}" ]; then
    echo "✅ All critical assets present!"
    echo ""
    echo "You can now build the APK:"
    echo "  cd android"
    echo "  ./gradlew assembleDebug"
else
    echo "⚠️  Some critical assets are missing. Please complete asset acquisition."
fi
