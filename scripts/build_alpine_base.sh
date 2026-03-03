#!/bin/bash
# Build a minimal Alpine 3.19 aarch64 rootfs for the QEMU VM.
# Uses a native linux/arm64 Alpine container with "apk --root" (no chroot, no binfmt_misc).
# Outputs: android/app/src/main/assets/vm/base.qcow2.gz
#
# Requirements: Docker (Colima or Docker Desktop) with arm64 container support.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_VM_DIR="${PROJECT_ROOT}/android/app/src/main/assets/vm"
GUEST_DIR="${PROJECT_ROOT}/guest"

mkdir -p "${ASSETS_VM_DIR}"

echo "=== Building Alpine 3.19 aarch64 base image ==="
echo "Output: ${ASSETS_VM_DIR}/base.qcow2.gz"
echo ""

docker run --rm \
    --platform linux/arm64 \
    --privileged \
    -v "${ASSETS_VM_DIR}:/out" \
    -v "${GUEST_DIR}:/bootstrap_src:ro" \
    -v "${SCRIPT_DIR}/alpine_build_inner.sh:/build.sh:ro" \
    alpine:3.19 \
    sh /build.sh 2>&1
echo ""
echo "=== Build complete ==="
ls -lh "${ASSETS_VM_DIR}/base.qcow2.gz"
echo ""
echo "SHA-256:"
shasum -a 256 "${ASSETS_VM_DIR}/base.qcow2.gz"
exit 0

# ---- inner script below (also lives in alpine_build_inner.sh) ----
: << 'DOCKEREOF'
set -e

ALPINE_VERSION=3.19.1

echo "=== Installing host build tools ==="
apk add --no-cache e2fsprogs qemu-img wget

echo "=== Downloading Alpine ${ALPINE_VERSION} aarch64 minirootfs ==="
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
wget -q -O /tmp/minirootfs.tar.gz "$MINIROOTFS_URL"
echo "Downloaded: $(du -sh /tmp/minirootfs.tar.gz | cut -f1)"

echo "=== Creating 512MB ext4 raw disk ==="
dd if=/dev/zero of=/tmp/alpine.raw bs=1M count=512 status=none
mkfs.ext4 -F -L "alpine-root" -m 0 -q /tmp/alpine.raw

mkdir -p /mnt/alpine
mount -o loop /tmp/alpine.raw /mnt/alpine

echo "=== Extracting minirootfs ==="
tar xzf /tmp/minirootfs.tar.gz -C /mnt/alpine

# ---- APK repositories ----
cat > /mnt/alpine/etc/apk/repositories << 'REPOS'
https://dl-cdn.alpinelinux.org/alpine/v3.19/main
https://dl-cdn.alpinelinux.org/alpine/v3.19/community
REPOS

echo "=== Installing alpine-base + openrc via apk --root ==="
# No chroot — apk extracts tarballs and runs shell post-install scripts on the host.
# This avoids binfmt_misc / dynamic-linker issues entirely.
apk --root /mnt/alpine \
    --arch aarch64 \
    --repositories-file /mnt/alpine/etc/apk/repositories \
    add --no-cache \
    alpine-base openrc 2>&1 | tail -15
echo "APK exit: $?"

# ---- System config ----
echo "docker-vm" > /mnt/alpine/etc/hostname

cat > /mnt/alpine/etc/hosts << 'HOSTS'
127.0.0.1 localhost docker-vm
::1       localhost
HOSTS

# ---- QEMU SLIRP networking — static IP, no AF_PACKET / udhcpc needed ----
# SLIRP default: guest IP 10.0.2.15, gateway 10.0.2.2, DNS 10.0.2.3
mkdir -p /mnt/alpine/etc/network
cat > /mnt/alpine/etc/network/interfaces << 'NET'
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
  address 10.0.2.15
  netmask 255.255.255.0
  gateway 10.0.2.2
NET

echo "nameserver 10.0.2.3" > /mnt/alpine/etc/resolv.conf

# ---- Kernel modules to load at boot ----
# qemu_fw_cfg: exposes /sys/firmware/qemu_fw_cfg/ so the API token can be read
# loaded by OpenRC "modules" service (boot runlevel) before docker-bootstrap runs
echo "qemu_fw_cfg" >> /mnt/alpine/etc/modules

# ---- fstab ----
cat > /mnt/alpine/etc/fstab << 'FSTAB'
/dev/vda / ext4 rw,relatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
shm /dev/shm tmpfs defaults 0 0
tmp /tmp tmpfs nosuid,nodev 0 0
FSTAB

# ---- Bootstrap scripts ----
echo "=== Copying bootstrap scripts ==="
mkdir -p /mnt/alpine/bootstrap
cp /bootstrap_src/api_server.py /mnt/alpine/bootstrap/
cp /bootstrap_src/requirements.txt /mnt/alpine/bootstrap/
cp /bootstrap_src/init_bootstrap.sh /mnt/alpine/bootstrap/
chmod +x /mnt/alpine/bootstrap/init_bootstrap.sh

# ---- docker-bootstrap OpenRC service ----
cat > /mnt/alpine/etc/init.d/docker-bootstrap << 'RC'
#!/sbin/openrc-run
name="Docker Bootstrap"
description="Install Docker and start API server on first boot"

depend() {
    need networking
    after networking
}

start() {
    [ -f /bootstrap/.completed ] && return 0
    ebegin "Running Docker bootstrap (first boot only)"
    /bootstrap/init_bootstrap.sh
    local ret=$?
    [ $ret -eq 0 ] && touch /bootstrap/.completed
    eend $ret
}
RC
chmod +x /mnt/alpine/etc/init.d/docker-bootstrap

# ---- OpenRC runlevel symlinks (manual — no chroot, no rc-update) ----
echo "=== Configuring OpenRC runlevels ==="
mkdir -p /mnt/alpine/etc/runlevels/sysinit \
         /mnt/alpine/etc/runlevels/boot \
         /mnt/alpine/etc/runlevels/default \
         /mnt/alpine/etc/runlevels/shutdown

for svc in devfs dmesg; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/sysinit/$svc
done

for svc in modules sysctl hostname bootmisc syslog; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/boot/$svc
done

for svc in networking docker-bootstrap; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/default/$svc
done

for svc in killprocs mount-ro savecache; do
    [ -f /mnt/alpine/etc/init.d/$svc ] && \
        ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/shutdown/$svc || true
done

echo "Rootfs size: $(du -sh /mnt/alpine | cut -f1)"
df -h /mnt/alpine | tail -1

umount /mnt/alpine

echo "=== Converting raw → QCOW2 ==="
qemu-img convert -f raw -O qcow2 -c /tmp/alpine.raw /tmp/base.qcow2

echo "=== Compressing ==="
gzip -9 -c /tmp/base.qcow2 > /out/base.qcow2.gz

echo "=== Done ==="
ls -lh /out/base.qcow2.gz
qemu-img info /tmp/base.qcow2
DOCKEREOF

echo ""
echo "=== Build complete ==="
ls -lh "${ASSETS_VM_DIR}/base.qcow2.gz"
echo ""
echo "SHA-256:"
shasum -a 256 "${ASSETS_VM_DIR}/base.qcow2.gz"
