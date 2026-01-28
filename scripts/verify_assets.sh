#!/bin/bash
# Verify all assets are present and valid

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets"

echo "=== Asset Verification ==="
echo ""

ERRORS=0
WARNINGS=0

# Check directories
echo "Checking directories..."
for DIR in qemu vm bootstrap; do
    if [ -d "${ASSETS_DIR}/${DIR}" ]; then
        echo "  ✅ ${DIR}/ exists"
    else
        echo "  ❌ ${DIR}/ missing"
        ((ERRORS++))
    fi
done

echo ""

# Check QEMU binaries
echo "Checking QEMU binaries..."

QEMU_AARCH64="${ASSETS_DIR}/qemu/qemu-system-aarch64"
QEMU_IMG="${ASSETS_DIR}/qemu/qemu-img"

check_binary() {
    local binary=$1
    local name=$2
    local min_size=$3

    if [ ! -f "${binary}" ]; then
        echo "  ❌ ${name}: NOT FOUND"
        ((ERRORS++))
        return
    fi

    local size=$(stat -f%z "${binary}" 2>/dev/null || stat -c%s "${binary}" 2>/dev/null)
    local size_mb=$((size / 1024 / 1024))

    if [ ${size} -lt ${min_size} ]; then
        echo "  ⚠️  ${name}: Too small (${size_mb}MB)"
        ((WARNINGS++))
    else
        echo "  ✅ ${name}: ${size_mb}MB"
    fi

    # Check file type
    local file_type=$(file "${binary}")
    if echo "${file_type}" | grep -q "ELF.*aarch64"; then
        echo "      Architecture: aarch64 ✓"
    else
        echo "      ⚠️  Not aarch64 binary: ${file_type}"
        ((WARNINGS++))
    fi
}

check_binary "${QEMU_AARCH64}" "qemu-system-aarch64" $((10 * 1024 * 1024))
check_binary "${QEMU_IMG}" "qemu-img" $((1 * 1024 * 1024))

echo ""

# Check Alpine image
echo "Checking Alpine Linux image..."

BASE_IMAGE="${ASSETS_DIR}/vm/base.qcow2.gz"

if [ ! -f "${BASE_IMAGE}" ]; then
    echo "  ❌ base.qcow2.gz: NOT FOUND"
    ((ERRORS++))
else
    local size=$(stat -f%z "${BASE_IMAGE}" 2>/dev/null || stat -c%s "${BASE_IMAGE}" 2>/dev/null)
    local size_mb=$((size / 1024 / 1024))

    if [ ${size} -lt $((30 * 1024 * 1024)) ]; then
        echo "  ⚠️  base.qcow2.gz: Too small (${size_mb}MB)"
        ((WARNINGS++))
    elif [ ${size} -gt $((100 * 1024 * 1024)) ]; then
        echo "  ⚠️  base.qcow2.gz: Too large (${size_mb}MB)"
        ((WARNINGS++))
    else
        echo "  ✅ base.qcow2.gz: ${size_mb}MB"
    fi

    # Check if it's gzip
    if file "${BASE_IMAGE}" | grep -q "gzip"; then
        echo "      Format: gzip ✓"
    else
        echo "      ⚠️  Not gzip compressed"
        ((WARNINGS++))
    fi
fi

echo ""

# Check bootstrap scripts
echo "Checking bootstrap scripts..."

BOOTSTRAP_FILES=(
    "api_server.py"
    "init_bootstrap.sh"
    "requirements.txt"
)

for FILE in "${BOOTSTRAP_FILES[@]}"; do
    FILE_PATH="${ASSETS_DIR}/bootstrap/${FILE}"

    if [ ! -f "${FILE_PATH}" ]; then
        echo "  ❌ ${FILE}: NOT FOUND"
        ((ERRORS++))
    else
        local size=$(wc -c < "${FILE_PATH}")

        if [ ${size} -eq 0 ]; then
            echo "  ❌ ${FILE}: EMPTY"
            ((ERRORS++))
        else
            echo "  ✅ ${FILE}: ${size} bytes"

            # Check if executable for .sh and .py files
            if [[ "${FILE}" == *.sh ]] || [[ "${FILE}" == *.py ]]; then
                if [ -x "${FILE_PATH}" ]; then
                    echo "      Executable: ✓"
                else
                    echo "      ⚠️  Not executable (will be set by AssetManager)"
                fi
            fi
        fi
    fi
done

echo ""

# Check checksums file
echo "Checking checksums..."

CHECKSUM_FILE="${ASSETS_DIR}/checksums.txt"

if [ -f "${CHECKSUM_FILE}" ]; then
    echo "  ✅ checksums.txt exists"
    local count=$(wc -l < "${CHECKSUM_FILE}")
    echo "      Contains ${count} checksums"
else
    echo "  ⚠️  checksums.txt not found"
    echo "      Run: ./scripts/generate_checksums.sh"
    ((WARNINGS++))
fi

echo ""

# Calculate total size
echo "=== Asset Size Summary ==="
echo ""

if [ -d "${ASSETS_DIR}/qemu" ]; then
    echo "QEMU binaries:     $(du -sh ${ASSETS_DIR}/qemu | awk '{print $1}')"
fi

if [ -d "${ASSETS_DIR}/vm" ]; then
    echo "VM images:         $(du -sh ${ASSETS_DIR}/vm | awk '{print $1}')"
fi

if [ -d "${ASSETS_DIR}/bootstrap" ]; then
    echo "Bootstrap scripts: $(du -sh ${ASSETS_DIR}/bootstrap | awk '{print $1}')"
fi

echo "───────────────────────"
echo "Total assets:      $(du -sh ${ASSETS_DIR} | awk '{print $1}')"

echo ""

# Final verdict
echo "=== Verification Results ==="
echo ""
echo "Errors:   ${ERRORS}"
echo "Warnings: ${WARNINGS}"
echo ""

if [ ${ERRORS} -eq 0 ] && [ ${WARNINGS} -eq 0 ]; then
    echo "✅ All assets verified successfully!"
    echo ""
    echo "Ready to build APK:"
    echo "  cd android"
    echo "  ./gradlew assembleDebug"
elif [ ${ERRORS} -eq 0 ]; then
    echo "⚠️  Assets present with some warnings."
    echo "You can proceed but may encounter issues."
else
    echo "❌ Asset verification failed."
    echo ""
    echo "Missing assets. Please run:"
    echo "  ./scripts/setup_assets.sh"
    echo ""
    echo "Or see ASSET_GUIDE.md for manual instructions."
    exit 1
fi
