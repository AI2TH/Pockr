#!/bin/bash
# Download and prepare Alpine Linux image for the Docker VM app.
# All download and conversion steps run inside a Docker container —
# no host-side qemu-img or wget/curl required beyond Docker itself.

set -e

ALPINE_VERSION="3.19"
ALPINE_RELEASE="3.19.1"
ARCH="aarch64"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ISO_URL="${ALPINE_MIRROR}/v${ALPINE_VERSION}/releases/${ARCH}/alpine-virt-${ALPINE_RELEASE}-${ARCH}.iso"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_VM_DIR="${PROJECT_ROOT}/android/app/src/main/assets/vm"
WORK_DIR="${PROJECT_ROOT}/tools/downloads"

echo "=== Alpine Linux Image Download and Preparation ==="
echo "Version : ${ALPINE_RELEASE}"
echo "Arch    : ${ARCH}"
echo "Work dir: ${WORK_DIR}"
echo ""

mkdir -p "${WORK_DIR}" "${ASSETS_VM_DIR}"

# Verify Docker is available
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required but not found. Install Docker Desktop and try again."
    exit 1
fi

# ---------------------------------------------------------------------------
# Run all download + conversion steps inside a Docker container.
# Uses debian:bookworm-slim with qemu-utils and wget.
# The WORK_DIR is mounted so outputs land on the host.
# ---------------------------------------------------------------------------

echo "Launching Docker container for download and conversion..."

docker run --rm \
    --platform linux/amd64 \
    -v "${WORK_DIR}:/work" \
    -e "ISO_URL=${ISO_URL}" \
    -e "ALPINE_RELEASE=${ALPINE_RELEASE}" \
    -e "ARCH=${ARCH}" \
    debian:bookworm-slim \
    bash -c '
set -e
echo "Installing tools..."
apt-get update -qq
apt-get install -y -qq wget qemu-utils gzip coreutils

ISO_FILE="/work/alpine-virt-${ALPINE_RELEASE}-${ARCH}.iso"
QCOW2_FILE="/work/base.qcow2"
COMPRESSED_FILE="/work/base.qcow2.gz"

# Download ISO
if [ -f "${ISO_FILE}" ]; then
    echo "ISO already downloaded: ${ISO_FILE}"
else
    echo "Downloading Alpine Linux ${ALPINE_RELEASE} (${ARCH})..."
    wget -q --show-progress -O "${ISO_FILE}" "${ISO_URL}"
    echo "Download complete."
fi

# Verify minimum size (Alpine virt ISO is ~50 MB)
ISO_SIZE=$(wc -c < "${ISO_FILE}")
if [ "${ISO_SIZE}" -lt 10000000 ]; then
    echo "ERROR: ISO too small (${ISO_SIZE} bytes) — download may have failed."
    exit 1
fi

# Convert ISO → QCOW2
echo "Converting ISO to QCOW2..."
qemu-img convert -f raw -O qcow2 "${ISO_FILE}" "${QCOW2_FILE}"

echo "QCOW2 info:"
qemu-img info "${QCOW2_FILE}"

# Compress
echo "Compressing (gzip -9)..."
gzip -9 -c "${QCOW2_FILE}" > "${COMPRESSED_FILE}"

# Checksums
echo ""
echo "=== Checksums ==="
sha256sum "${COMPRESSED_FILE}"
sha256sum "${QCOW2_FILE}"

echo ""
echo "=== Sizes ==="
ls -lh "${ISO_FILE}" "${QCOW2_FILE}" "${COMPRESSED_FILE}"
echo ""
echo "Done inside container."
'

echo ""
echo "=== Copying compressed image to assets ==="
cp "${WORK_DIR}/base.qcow2.gz" "${ASSETS_VM_DIR}/base.qcow2.gz"
echo "Copied to: ${ASSETS_VM_DIR}/base.qcow2.gz"

echo ""
echo "SHA-256 (assets copy):"
shasum -a 256 "${ASSETS_VM_DIR}/base.qcow2.gz"

echo ""
echo "✅  Alpine Linux image ready at android/app/src/main/assets/vm/base.qcow2.gz"
echo ""
echo "Next: run scripts/extract_from_termux.sh to get QEMU binaries."
