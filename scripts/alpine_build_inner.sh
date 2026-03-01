set -e

ALPINE_VERSION=3.19.1

echo "=== Installing host build tools ==="
apk add --no-cache e2fsprogs qemu-img wget python3 py3-pip

echo "=== Downloading Alpine ${ALPINE_VERSION} aarch64 minirootfs ==="
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
wget -q -O /tmp/minirootfs.tar.gz "$MINIROOTFS_URL"
echo "Downloaded: $(du -sh /tmp/minirootfs.tar.gz | cut -f1)"

echo "=== Creating 1GB ext4 raw disk ==="
dd if=/dev/zero of=/tmp/alpine.raw bs=1M count=1024 status=none
mkfs.ext4 -F -L "alpine-root" -m 0 -q /tmp/alpine.raw

mkdir -p /mnt/alpine
mount -o loop /tmp/alpine.raw /mnt/alpine

echo "=== Extracting minirootfs ==="
tar xzf /tmp/minirootfs.tar.gz -C /mnt/alpine

cat > /mnt/alpine/etc/apk/repositories << 'REPOS'
https://dl-cdn.alpinelinux.org/alpine/v3.19/main
https://dl-cdn.alpinelinux.org/alpine/v3.19/community
REPOS

echo "=== Installing alpine-base, openrc, docker, python3 via apk --root ==="
apk --root /mnt/alpine \
    --arch aarch64 \
    --repositories-file /mnt/alpine/etc/apk/repositories \
    add --no-cache \
    alpine-base openrc docker python3 2>&1 | tail -25
echo "APK exit: $?"

echo "=== Pre-installing Python API server dependencies ==="
# Install pip packages into the target rootfs from the host.
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

echo "nameserver 10.0.2.3" > /mnt/alpine/etc/resolv.conf

cat > /mnt/alpine/etc/fstab << 'FSTAB'
/dev/vda / ext4 rw,relatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
shm /dev/shm tmpfs defaults 0 0
tmp /tmp tmpfs nosuid,nodev 0 0
FSTAB

echo "=== Docker daemon config ==="
# iptables-nft requires CONFIG_NF_TABLES in kernel. The Alpine 6.6.14-0-virt
# kernel has nf_tables as a module, but /lib/modules is absent in our rootfs
# (we only ship vmlinuz + initramfs, not the full linux-virt package).
# Disabling iptables lets Docker start without needing netfilter modules.
# docker pull/run still work; container internet NAT is absent until we add
# linux-virt kernel modules.
mkdir -p /mnt/alpine/etc/docker
cat > /mnt/alpine/etc/docker/daemon.json << 'DOCKERCFG'
{
  "iptables": false,
  "bridge": "none",
  "ip-masq": false,
  "userland-proxy": false
}
DOCKERCFG

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
for svc in networking docker docker-bootstrap; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/default/$svc
done

echo "=== Rootfs stats ==="
echo "Rootfs size: $(du -sh /mnt/alpine | cut -f1)"
df -h /mnt/alpine | tail -1

umount /mnt/alpine

echo "=== Converting raw to QCOW2 ==="
qemu-img convert -f raw -O qcow2 -c /tmp/alpine.raw /tmp/base.qcow2

echo "=== Compressing ==="
gzip -9 -c /tmp/base.qcow2 > /out/base.qcow2.gz

echo "=== Done ==="
ls -lh /out/base.qcow2.gz
qemu-img info /tmp/base.qcow2
