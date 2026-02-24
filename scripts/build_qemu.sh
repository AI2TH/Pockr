#!/bin/bash
# Build QEMU for Android ARM64 inside Docker.
# Cross-compiles qemu-system-aarch64 and qemu-img targeting aarch64-linux
# from an x86_64 Docker container using the aarch64-linux-gnu toolchain.
#
# Output: android/app/src/main/assets/qemu/qemu-system-aarch64
#         android/app/src/main/assets/qemu/qemu-img
#
# Note: This takes ~20–30 minutes on first run. The resulting binary runs on
# aarch64 Android devices without root.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_QEMU="${PROJECT_ROOT}/android/app/src/main/assets/qemu"
QEMU_VERSION="${QEMU_VERSION:-8.2.0}"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required."
    exit 1
fi

echo "=== Building QEMU ${QEMU_VERSION} for Android ARM64 (via Docker) ==="
echo "Output: android/app/src/main/assets/qemu/"
echo ""
echo "This builds inside a Docker container. Expected time: 20–30 min."
echo ""

mkdir -p "${ASSETS_QEMU}"

# ── Build inside a Debian bookworm container ──────────────────────────────────
# Uses the aarch64-linux-gnu cross-compiler. The resulting ELF aarch64 binary
# links against glibc; Android 5.0+ ships glibc-compatible libc (Bionic),
# so the binary works on modern Android devices without extra libraries.
#
# We build only the aarch64-softmmu target (system emulator) and qemu-img.
# TCG (software emulation) is the default — KVM is not assumed.
# ─────────────────────────────────────────────────────────────────────────────

docker run --rm \
    --platform linux/amd64 \
    -v "${ASSETS_QEMU}:/out" \
    -e "QEMU_VERSION=${QEMU_VERSION}" \
    debian:bookworm \
    bash -c '
set -e

echo "Installing build dependencies..."
apt-get update -qq
apt-get install -y -qq \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    python3 python3-pip meson ninja-build \
    pkg-config libglib2.0-dev libffi-dev zlib1g-dev \
    git wget curl ca-certificates \
    flex bison \
    libpixman-1-dev:arm64 \
    gcc-aarch64-linux-gnu \
    libglib2.0-dev:arm64 \
    2>/dev/null || true

# Enable arm64 packages
dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq \
    libglib2.0-dev:arm64 \
    libffi-dev:arm64 \
    zlib1g-dev:arm64 \
    libpixman-1-dev:arm64 \
    2>/dev/null || true

echo ""
echo "Downloading QEMU ${QEMU_VERSION} source..."
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

wget -q "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz"
echo "Extracting..."
tar -xf "qemu-${QEMU_VERSION}.tar.xz"
cd "qemu-${QEMU_VERSION}"

echo ""
echo "Configuring QEMU (cross-compile: aarch64-linux-gnu)..."
mkdir build && cd build

../configure \
    --cross-prefix=aarch64-linux-gnu- \
    --target-list=aarch64-softmmu \
    --enable-tools \
    --disable-docs \
    --disable-sdl \
    --disable-gtk \
    --disable-vnc \
    --disable-opengl \
    --disable-virglrenderer \
    --disable-spice \
    --disable-libnfs \
    --disable-libssh \
    --disable-curl \
    --disable-bochs \
    --disable-cloop \
    --disable-dmg \
    --disable-qcow1 \
    --disable-vdi \
    --disable-vvfat \
    --disable-qed \
    --disable-parallels \
    --disable-sheepdog \
    --disable-capstone \
    --enable-tcg \
    --static

echo ""
echo "Building (this takes 20–30 min)..."
make -j$(nproc) qemu-system-aarch64 qemu-img

echo ""
echo "Stripping binaries..."
aarch64-linux-gnu-strip qemu-system-aarch64
aarch64-linux-gnu-strip qemu-img

echo "Copying to output..."
cp qemu-system-aarch64 /out/
cp qemu-img /out/

echo ""
echo "=== Build Output ==="
ls -lh /out/qemu-system-aarch64 /out/qemu-img
file /out/qemu-system-aarch64
file /out/qemu-img

echo ""
echo "SHA-256:"
sha256sum /out/qemu-system-aarch64
sha256sum /out/qemu-img
'

echo ""
echo "✅  QEMU ${QEMU_VERSION} built and saved to android/app/src/main/assets/qemu/"
echo ""
echo "Verify with:"
echo "  ./scripts/verify_assets.sh"
