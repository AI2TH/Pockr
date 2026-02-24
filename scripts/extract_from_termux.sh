#!/bin/bash
# Extract QEMU binaries from a running Termux installation (via adb)
# or from downloaded Termux .deb packages (extraction via Docker).
#
# All .deb extraction is done inside Docker — no host-side ar/dpkg-deb needed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets/qemu"
TOOLS_DIR="${PROJECT_ROOT}/tools/termux_packages"

echo "=== Extract QEMU Binaries from Termux ==="
echo ""
echo "Option 1: Pull directly from a device running Termux (via adb)"
echo "Option 2: Extract from downloaded Termux .deb packages (uses Docker)"
echo ""
read -r -p "Choose option (1 or 2): " REPLY
echo ""

mkdir -p "${ASSETS_DIR}" "${TOOLS_DIR}"

if [[ $REPLY == "1" ]]; then
    # ------------------------------------------------------------------
    # Option 1: adb pull from device with Termux + QEMU installed
    # ------------------------------------------------------------------
    echo "=== Option 1: Extract via ADB ==="
    echo ""

    if ! command -v adb &>/dev/null; then
        echo "ERROR: adb not found. Install Android SDK Platform Tools."
        exit 1
    fi

    DEVICE_COUNT=$(adb devices | grep -c -w "device" || true)
    if [ "${DEVICE_COUNT}" -eq 0 ]; then
        echo "ERROR: No Android devices connected. Connect your device and enable USB debugging."
        exit 1
    fi

    echo "Device connected."
    echo ""
    echo "Make sure Termux is installed and you have run inside Termux:"
    echo "  pkg update && pkg install qemu-system-aarch64-headless qemu-utils"
    echo ""
    read -r -p "Ready to pull? (y/n) " READY
    echo ""
    if [[ ! $READY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    TERMUX_BIN="/data/data/com.termux/files/usr/bin"

    echo "Pulling qemu-system-aarch64..."
    adb pull "${TERMUX_BIN}/qemu-system-aarch64" "${ASSETS_DIR}/qemu-system-aarch64"

    echo "Pulling qemu-img..."
    adb pull "${TERMUX_BIN}/qemu-img" "${ASSETS_DIR}/qemu-img"

    echo ""
    echo "✅  Binaries pulled via adb."

elif [[ $REPLY == "2" ]]; then
    # ------------------------------------------------------------------
    # Option 2: Extract from .deb files using Docker
    # ------------------------------------------------------------------
    echo "=== Option 2: Extract from .deb packages via Docker ==="
    echo ""

    if ! command -v docker &>/dev/null; then
        echo "ERROR: Docker is required but not found."
        exit 1
    fi

    echo "Download the following .deb files from Termux package repo:"
    echo "  https://packages.termux.dev/apt/termux-main/pool/main/"
    echo "  - qemu-system-aarch64-headless_*_aarch64.deb"
    echo "  - qemu-utils_*_aarch64.deb"
    echo ""
    echo "Place the .deb files in: ${TOOLS_DIR}"
    echo ""
    read -r -p "Have you downloaded the .deb files? (y/n) " READY
    echo ""
    if [[ ! $READY =~ ^[Yy]$ ]]; then
        echo "Aborted. Download the .deb files then re-run."
        exit 0
    fi

    DEB_COUNT=$(find "${TOOLS_DIR}" -name "*.deb" 2>/dev/null | wc -l)
    if [ "${DEB_COUNT}" -eq 0 ]; then
        echo "ERROR: No .deb files found in ${TOOLS_DIR}."
        exit 1
    fi

    echo "Found ${DEB_COUNT} .deb file(s). Extracting via Docker..."
    echo ""

    docker run --rm \
        --platform linux/amd64 \
        -v "${TOOLS_DIR}:/debs:ro" \
        -v "${ASSETS_DIR}:/out" \
        debian:bookworm-slim \
        bash -c '
set -e
apt-get update -qq
apt-get install -y -qq binutils  # provides ar

TERMUX_PREFIX="data/data/com.termux/files/usr"

for DEB in /debs/*.deb; do
    echo "Processing: $(basename $DEB)"
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"

    # .deb is an ar archive; extract data.tar.*
    ar -x "$DEB" 2>/dev/null

    if [ -f data.tar.xz ]; then
        tar -xf data.tar.xz
    elif [ -f data.tar.gz ]; then
        tar -xf data.tar.gz
    elif [ -f data.tar.zst ]; then
        # zstd may not be installed; try tar fallback
        apt-get install -y -qq zstd && tar -xf data.tar.zst
    else
        echo "  WARNING: unknown data archive format in $(basename $DEB)"
    fi

    for BIN in qemu-system-aarch64 qemu-img; do
        SRC="${TMPDIR}/${TERMUX_PREFIX}/bin/${BIN}"
        if [ -f "$SRC" ]; then
            cp "$SRC" /out/
            echo "  ✓ Extracted $BIN"
        fi
    done

    cd /
    rm -rf "$TMPDIR"
done

echo ""
echo "Files in output directory:"
ls -lh /out/
'

    echo ""
    echo "✅  Binaries extracted from .deb packages."

else
    echo "Invalid option."
    exit 1
fi

# ------------------------------------------------------------------
# Verify
# ------------------------------------------------------------------
echo ""
echo "=== Verifying Binaries ==="
for BIN in qemu-system-aarch64 qemu-img; do
    BIN_PATH="${ASSETS_DIR}/${BIN}"
    if [ ! -f "${BIN_PATH}" ]; then
        echo "❌  ${BIN}: NOT FOUND at ${BIN_PATH}"
        continue
    fi
    FILE_TYPE=$(file "${BIN_PATH}")
    echo ""
    echo "${BIN}:"
    echo "  Size : $(ls -lh "${BIN_PATH}" | awk '{print $5}')"
    echo "  Type : ${FILE_TYPE}"
    if echo "${FILE_TYPE}" | grep -q "ELF 64-bit.*aarch64"; then
        echo "  ✅   Valid aarch64 ELF"
    else
        echo "  ⚠️   Warning: may not be aarch64 binary"
    fi
    echo "  SHA-256: $(shasum -a 256 "${BIN_PATH}" | awk '{print $1}')"
done

echo ""
echo "=== Done ==="
echo "Binaries saved to: ${ASSETS_DIR}"
echo ""

MISSING=0
for BIN in qemu-system-aarch64 qemu-img; do
    [ -f "${ASSETS_DIR}/${BIN}" ] || MISSING=1
done

if [ $MISSING -eq 0 ]; then
    echo "✅  All required binaries present."
    echo ""
    echo "Next: run scripts/download_alpine.sh to prepare the Alpine Linux image."
else
    echo "❌  Some binaries are missing. Check extraction output above."
    exit 1
fi
