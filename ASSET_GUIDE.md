# Asset Acquisition Guide

This guide explains how to obtain QEMU binaries and Alpine Linux images for the Docker VM app.

## Overview

The app requires these assets to be placed in `android/app/src/main/assets/`:
- `qemu/qemu-system-aarch64` - QEMU system emulator (~15-20MB)
- `qemu/qemu-img` - QEMU disk image utility (~2-3MB)
- `vm/base.qcow2.gz` - Compressed Alpine Linux base image (~50MB)
- `bootstrap/` - Guest initialization scripts (already in repo)

## Option 1: Extract from Termux (Recommended)

This is the easiest method as Termux provides pre-built Android binaries.

### Steps:

1. **Install Termux**
   - Download from F-Droid: https://f-droid.org/en/packages/com.termux/
   - Do NOT use Google Play version (outdated)

2. **Install QEMU in Termux**
   ```bash
   pkg update
   pkg install qemu-system-aarch64-headless qemu-utils
   ```

3. **Locate the binaries**
   ```bash
   which qemu-system-aarch64  # /data/data/com.termux/files/usr/bin/qemu-system-aarch64
   which qemu-img             # /data/data/com.termux/files/usr/bin/qemu-img
   ```

4. **Copy binaries to your development machine**

   Using adb:
   ```bash
   adb pull /data/data/com.termux/files/usr/bin/qemu-system-aarch64 ./qemu-system-aarch64
   adb pull /data/data/com.termux/files/usr/bin/qemu-img ./qemu-img
   ```

   Or using Termux:
   ```bash
   # Inside Termux
   cp /data/data/com.termux/files/usr/bin/qemu-system-aarch64 /sdcard/Download/
   cp /data/data/com.termux/files/usr/bin/qemu-img /sdcard/Download/
   # Then copy from Downloads folder to your dev machine
   ```

5. **Copy to project assets**
   ```bash
   mkdir -p android/app/src/main/assets/qemu
   cp qemu-system-aarch64 android/app/src/main/assets/qemu/
   cp qemu-img android/app/src/main/assets/qemu/
   ```

6. **Verify binaries**
   ```bash
   file android/app/src/main/assets/qemu/qemu-system-aarch64
   # Should show: ELF 64-bit LSB executable, ARM aarch64
   ```

## Option 2: Build from Source

If you need custom builds or can't use Termux binaries:

1. **Set up Android NDK**
   - Download Android NDK: https://developer.android.com/ndk/downloads
   - Extract and set `ANDROID_NDK_ROOT`

2. **Clone QEMU source**
   ```bash
   git clone https://gitlab.com/qemu-project/qemu.git
   cd qemu
   git checkout v8.2.0  # Use stable version
   ```

3. **Configure for Android**
   ```bash
   ./configure \
     --cross-prefix=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android- \
     --target-list=aarch64-softmmu \
     --enable-user \
     --disable-linux-user \
     --disable-bsd-user \
     --disable-docs \
     --disable-gtk \
     --disable-sdl \
     --disable-vnc
   ```

4. **Build**
   ```bash
   make -j$(nproc)
   ```

5. **Strip binaries to reduce size**
   ```bash
   aarch64-linux-android-strip qemu-system-aarch64
   aarch64-linux-android-strip qemu-img
   ```

## Alpine Linux Image

### Download and Prepare

1. **Download Alpine Linux**
   ```bash
   # Download Alpine virt image for aarch64
   wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-virt-3.19.1-aarch64.iso
   ```

2. **Convert to QCOW2**
   ```bash
   qemu-img convert -f raw -O qcow2 alpine-virt-3.19.1-aarch64.iso base.qcow2
   ```

3. **Optional: Customize the image**

   You can boot the image locally, install packages, and create a snapshot:
   ```bash
   qemu-system-aarch64 \
     -machine virt \
     -cpu cortex-a53 \
     -m 2048 \
     -drive file=base.qcow2,format=qcow2 \
     -nographic

   # Inside VM:
   # - Set up Alpine
   # - Install Docker
   # - Install Python and FastAPI
   # - Copy bootstrap scripts
   # - Shutdown
   ```

4. **Compress the image**
   ```bash
   gzip -9 base.qcow2
   # Creates base.qcow2.gz (~50MB)
   ```

5. **Copy to project assets**
   ```bash
   mkdir -p android/app/src/main/assets/vm
   cp base.qcow2.gz android/app/src/main/assets/vm/
   ```

## Bootstrap Scripts

The bootstrap scripts are already in the `guest/` directory. Copy them to assets:

```bash
mkdir -p android/app/src/main/assets/bootstrap
cp guest/api_server.py android/app/src/main/assets/bootstrap/
cp guest/requirements.txt android/app/src/main/assets/bootstrap/
cp guest/init_bootstrap.sh android/app/src/main/assets/bootstrap/
```

## Generate Checksums

After placing all assets, generate SHA-256 checksums:

```bash
cd android/app/src/main/assets
find . -type f -exec sha256sum {} \; > checksums.txt
```

Sample checksums.txt:
```
abc123... ./qemu/qemu-system-aarch64
def456... ./qemu/qemu-img
789ghi... ./vm/base.qcow2.gz
```

## Verify Asset Sizes

Expected sizes:
- `qemu-system-aarch64`: 15-20MB
- `qemu-img`: 2-3MB
- `base.qcow2.gz`: 45-55MB
- Total assets: ~65-75MB

Total APK size will be approximately 70-80MB.

## Troubleshooting

### Binary won't execute on Android
- Ensure the binary is built for the correct architecture (aarch64)
- Check that it's not dependent on libraries not available on Android
- Verify executable permissions will be set by AssetManager

### Image too large
- Use Alpine virt (not standard) - it's minimal
- Remove unnecessary packages before compressing
- Compress with maximum compression: `gzip -9`

### QEMU crashes on Android
- Some devices have SELinux restrictions
- Test on multiple devices
- Check logcat for specific errors

## Next Steps

After acquiring assets:
1. Place them in the correct directories
2. Generate checksums
3. Update VmManager.kt to extract and verify assets
4. Test VM launch on a real Android device

## References

- Termux packages: https://github.com/termux/termux-packages
- QEMU documentation: https://www.qemu.org/docs/
- Alpine Linux: https://alpinelinux.org/downloads/
- ARC_START.md: Phase 2 - Asset Acquisition and Preparation
