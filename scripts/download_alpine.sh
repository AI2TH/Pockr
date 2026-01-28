#!/bin/bash
# Download and prepare Alpine Linux image for the Docker VM app

set -e

ALPINE_VERSION="3.19"
ALPINE_RELEASE="3.19.1"
ARCH="aarch64"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ISO_URL="${ALPINE_MIRROR}/v${ALPINE_VERSION}/releases/${ARCH}/alpine-virt-${ALPINE_RELEASE}-${ARCH}.iso"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets/vm"
DOWNLOAD_DIR="${PROJECT_ROOT}/tools/downloads"

echo "=== Alpine Linux Image Download and Preparation ==="
echo "Version: ${ALPINE_RELEASE}"
echo "Architecture: ${ARCH}"
echo ""

# Create directories
mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${ASSETS_DIR}"

ISO_FILE="${DOWNLOAD_DIR}/alpine-virt-${ALPINE_RELEASE}-${ARCH}.iso"
QCOW2_FILE="${DOWNLOAD_DIR}/base.qcow2"
COMPRESSED_FILE="${ASSETS_DIR}/base.qcow2.gz"

# Download ISO if not already downloaded
if [ -f "${ISO_FILE}" ]; then
    echo "Alpine ISO already downloaded: ${ISO_FILE}"
else
    echo "Downloading Alpine Linux ISO..."
    if command -v wget &> /dev/null; then
        wget -O "${ISO_FILE}" "${ISO_URL}"
    elif command -v curl &> /dev/null; then
        curl -L -o "${ISO_FILE}" "${ISO_URL}"
    else
        echo "ERROR: Neither wget nor curl found. Please install one."
        exit 1
    fi
    echo "Download complete!"
fi

# Verify ISO size
ISO_SIZE=$(wc -c < "${ISO_FILE}")
echo "ISO size: $(numfmt --to=iec-i --suffix=B ${ISO_SIZE})"

if [ ${ISO_SIZE} -lt 10000000 ]; then
    echo "ERROR: ISO file is too small. Download may have failed."
    exit 1
fi

# Check for qemu-img
if ! command -v qemu-img &> /dev/null; then
    echo ""
    echo "WARNING: qemu-img not found!"
    echo "Please install QEMU tools:"
    echo "  macOS: brew install qemu"
    echo "  Ubuntu/Debian: sudo apt-get install qemu-utils"
    echo "  Fedora: sudo dnf install qemu-img"
    echo ""
    echo "After installing, run this script again."
    exit 1
fi

# Convert ISO to QCOW2
if [ -f "${QCOW2_FILE}" ]; then
    echo "QCOW2 image already exists: ${QCOW2_FILE}"
    read -p "Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping conversion..."
    else
        echo "Converting ISO to QCOW2..."
        qemu-img convert -f raw -O qcow2 "${ISO_FILE}" "${QCOW2_FILE}"
    fi
else
    echo "Converting ISO to QCOW2..."
    qemu-img convert -f raw -O qcow2 "${ISO_FILE}" "${QCOW2_FILE}"
fi

# Show QCOW2 info
echo ""
echo "QCOW2 image info:"
qemu-img info "${QCOW2_FILE}"

# Compress QCOW2
echo ""
echo "Compressing QCOW2 image..."
if [ -f "${COMPRESSED_FILE}" ]; then
    echo "Compressed image already exists: ${COMPRESSED_FILE}"
    read -p "Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping compression..."
    else
        echo "Compressing with gzip -9..."
        gzip -9 -c "${QCOW2_FILE}" > "${COMPRESSED_FILE}"
    fi
else
    echo "Compressing with gzip -9..."
    gzip -9 -c "${QCOW2_FILE}" > "${COMPRESSED_FILE}"
fi

# Show final sizes
echo ""
echo "=== Summary ==="
echo "Original ISO:     $(ls -lh ${ISO_FILE} | awk '{print $5}')"
echo "QCOW2 image:      $(ls -lh ${QCOW2_FILE} | awk '{print $5}')"
echo "Compressed:       $(ls -lh ${COMPRESSED_FILE} | awk '{print $5}')"
echo ""
echo "Compressed image saved to:"
echo "  ${COMPRESSED_FILE}"
echo ""
echo "SHA-256 checksum:"
shasum -a 256 "${COMPRESSED_FILE}"
echo ""
echo "✅ Alpine Linux image ready!"
