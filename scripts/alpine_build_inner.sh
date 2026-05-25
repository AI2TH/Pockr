set -e

ALPINE_VERSION=3.19.1

echo "=== Installing host build tools ==="
apk add --no-cache e2fsprogs qemu-img wget python3 py3-pip

echo "=== Downloading Alpine ${ALPINE_VERSION} aarch64 minirootfs ==="
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
wget -q -O /tmp/minirootfs.tar.gz "$MINIROOTFS_URL"
echo "Downloaded: $(du -sh /tmp/minirootfs.tar.gz | cut -f1)"

echo "=== Creating 2GB ext4 raw disk ==="
# 2GB: Docker images (alpine ~7MB, nginx ~40MB) + layers need room.
# 1GB was too tight — `docker pull` would hit ENOSPC.
dd if=/dev/zero of=/tmp/alpine.raw bs=1M count=2048 status=none
mkfs.ext4 -F -L "alpine-root" -m 0 -q /tmp/alpine.raw

mkdir -p /mnt/alpine
mount -o loop /tmp/alpine.raw /mnt/alpine

echo "=== Extracting minirootfs ==="
tar xzf /tmp/minirootfs.tar.gz -C /mnt/alpine

cat > /mnt/alpine/etc/apk/repositories << 'REPOS'
https://dl-cdn.alpinelinux.org/alpine/v3.19/main
https://dl-cdn.alpinelinux.org/alpine/v3.19/community
REPOS

echo "=== Installing packages (alpine-base, openrc, docker, python3, linux-virt) ==="
# linux-virt provides:
#   /lib/modules/<ver>/ — kernel modules for bridge, netfilter, cgroups
#   /boot/vmlinuz-virt  — kernel (we extract this for QEMU -kernel)
#   /boot/initramfs-virt — initrd (we extract this for QEMU -initrd)
# Without /lib/modules, Docker cannot create bridge networks or set up
# iptables NAT rules, making containers unable to reach the internet.
apk --root /mnt/alpine \
    --arch aarch64 \
    --repositories-file /mnt/alpine/etc/apk/repositories \
    add --no-cache \
    alpine-base openrc docker python3 linux-virt 2>&1 | tail -30
echo "APK exit: $?"

echo "=== Extracting kernel + initramfs for QEMU -kernel ==="
# Copy vmlinuz and initramfs to /out (assets/vm/) so Android can pass them
# directly to QEMU via -kernel/-initrd.  This ensures the kernel version
# matches the modules in /lib/modules/ inside the rootfs.
cp /mnt/alpine/boot/vmlinuz-virt /out/vmlinuz-virt
cp /mnt/alpine/boot/initramfs-virt /out/initramfs-virt
echo "Kernel: $(ls -lh /out/vmlinuz-virt | awk '{print $5}')"
echo "Initrd: $(ls -lh /out/initramfs-virt | awk '{print $5}')"

echo "=== Pre-installing Python API server dependencies ==="
# Both host and target are Alpine 3.19 aarch64 so packages are compatible.
pip3 install --break-system-packages \
    --root /mnt/alpine \
    --no-warn-script-location \
    --no-cache-dir \
    fastapi==0.109.0 uvicorn==0.27.0 pydantic==2.5.3 2>&1 | tail -10
echo "pip3 exit: $?"

echo "=== System config ==="
echo "docker-vm" > /mnt/alpine/etc/hostname

cat > /mnt/alpine/etc/hosts << 'HOSTS'
127.0.0.1 localhost docker-vm
::1       localhost
HOSTS

# QEMU SLIRP static IP — no udhcpc / AF_PACKET needed
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

# Try QEMU's internal DNS proxy first (10.0.2.3), then Google DNS directly.
# 'use-vc' forces TCP for all DNS queries — helps when SLIRP UDP is unreliable.
# 'timeout:2 attempts:2' keeps failure detection fast (default is 5s × 3).
printf 'nameserver 10.0.2.3\nnameserver 8.8.8.8\nnameserver 8.8.4.4\noptions timeout:2 attempts:2 use-vc\n' \
    > /mnt/alpine/etc/resolv.conf

cat > /mnt/alpine/etc/fstab << 'FSTAB'
/dev/vda / ext4 rw,relatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
shm /dev/shm tmpfs defaults 0 0
tmp /tmp tmpfs nosuid,nodev 0 0
cgroup2 /sys/fs/cgroup cgroup2 defaults 0 0
FSTAB

echo "=== Docker daemon config ==="
# With linux-virt installed, /lib/modules/ is present, so the kernel can load
# bridge, nf_tables, nf_nat, nf_conntrack on demand.  This means Docker can
# now create docker0, set up iptables NAT, and give containers internet access.
mkdir -p /mnt/alpine/etc/docker
cat > /mnt/alpine/etc/docker/daemon.json << 'DOCKERCFG'
{
  "storage-driver": "overlay2",
  "dns": ["8.8.8.8", "8.8.4.4"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "5m",
    "max-file": "2"
  }
}
DOCKERCFG

echo "=== Kernel module auto-load config ==="
# These modules must be loaded BEFORE Docker starts so it can create
# the docker0 bridge and set up iptables NAT rules.
cat > /mnt/alpine/etc/modules-load.d/docker.conf << 'MODULES'
# Base IPv4/IPv6 defrag (required before conntrack)
nf_defrag_ipv4
nf_defrag_ipv6
# Netfilter core
x_tables
nf_conntrack
nf_nat
# iptables extensions required for Docker NAT bridge
xt_conntrack
xt_MASQUERADE
xt_addrtype
ip_tables
iptable_filter
iptable_nat
# Bridge networking
bridge
br_netfilter
# Container networking
veth
# Overlay filesystem (Docker storage driver)
overlay
fuse
# Required for QEMU fw_cfg API token
qemu_fw_cfg
# virtio devices
virtio_blk
virtio_net
virtio_rng
MODULES

# Also keep /etc/modules for OpenRC 'modules' service (boot runlevel)
cat > /mnt/alpine/etc/modules << 'MODBOOT'
virtio_blk
virtio_net
virtio_rng
qemu_fw_cfg
nf_defrag_ipv4
nf_defrag_ipv6
x_tables
nf_conntrack
nf_nat
xt_conntrack
xt_MASQUERADE
xt_addrtype
ip_tables
iptable_filter
iptable_nat
bridge
br_netfilter
veth
overlay
fuse
MODBOOT

echo "=== Copying bootstrap scripts ==="
mkdir -p /mnt/alpine/bootstrap
cp /bootstrap_src/api_server.py /mnt/alpine/bootstrap/
cp /bootstrap_src/requirements.txt /mnt/alpine/bootstrap/
cp /bootstrap_src/init_bootstrap.sh /mnt/alpine/bootstrap/
chmod +x /mnt/alpine/bootstrap/init_bootstrap.sh

echo "=== docker-bootstrap OpenRC service ==="
cat > /mnt/alpine/etc/init.d/docker-bootstrap << 'RC'
#!/sbin/openrc-run
name="Docker Bootstrap"
description="Start API server (Docker pre-installed in base image)"

depend() {
    need docker
    after docker
}

start() {
    [ -f /bootstrap/.completed ] && return 0
    ebegin "Running bootstrap (first boot only)"
    /bootstrap/init_bootstrap.sh
    local ret=$?
    [ $ret -eq 0 ] && touch /bootstrap/.completed
    eend $ret
}
RC
chmod +x /mnt/alpine/etc/init.d/docker-bootstrap

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

# networking → docker → docker-bootstrap (ordered by depend() in each service)
for svc in networking cgroups docker docker-bootstrap; do
    [ -f /mnt/alpine/etc/init.d/$svc ] && \
        ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/default/$svc || \
        echo "WARNING: init script for $svc not found, skipping"
done

echo "=== Rootfs stats ==="
echo "Rootfs size: $(du -sh /mnt/alpine | cut -f1)"
df -h /mnt/alpine | tail -1
echo "Modules dir: $(ls /mnt/alpine/lib/modules/ 2>/dev/null || echo 'MISSING')"
echo "Module count: $(find /mnt/alpine/lib/modules/ -name '*.ko*' 2>/dev/null | wc -l)"

umount /mnt/alpine

echo "=== Converting raw to QCOW2 ==="
qemu-img convert -f raw -O qcow2 -c /tmp/alpine.raw /tmp/base.qcow2

echo "=== Compressing ==="
gzip -9 -c /tmp/base.qcow2 > /out/base.qcow2.gz

echo "=== Done ==="
ls -lh /out/base.qcow2.gz
ls -lh /out/vmlinuz-virt /out/initramfs-virt
qemu-img info /tmp/base.qcow2
