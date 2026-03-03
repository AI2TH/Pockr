# Phase 2: Asset Acquisition - Complete Guide

## Status: Partially Complete

✅ **Completed:**
- Bootstrap scripts copied to assets (3 files, ~10KB)
- Automation scripts created (6 shell scripts)

⏳ **Pending:**
- QEMU binaries (~17-23MB) - **Requires manual acquisition**
- Alpine Linux image (~50MB) - **Can be automated**

---

## Quick Start

Run the master setup script:

```bash
cd /Users/kalvin.nathan/Desktop/MAIN/kalvin/docker-app
./scripts/setup_assets.sh
```

This will show you an interactive menu to acquire assets.

---

## Option 1: Automated Alpine Download (Recommended First Step)

Download and prepare Alpine Linux image automatically:

```bash
./scripts/download_alpine.sh
```

**What this does:**
1. Downloads Alpine Linux 3.19.1 aarch64 ISO (~60MB)
2. Converts ISO to QCOW2 format
3. Compresses to base.qcow2.gz (~50MB)
4. Places in `android/app/src/main/assets/vm/`

**Requirements:**
- `qemu-img` tool (install: `brew install qemu` on macOS)
- `wget` or `curl`
- ~150MB free space (temporary)

**Time:** ~5-10 minutes (depending on download speed)

---

## Option 2: Extract QEMU from Termux

Extract QEMU binaries from Termux installation:

```bash
./scripts/extract_from_termux.sh
```

**Two methods:**

### Method A: From Device (via ADB)
**Requirements:**
- Android device with USB debugging enabled
- Termux installed from F-Droid
- QEMU packages installed in Termux

**Steps:**
1. On your Android device, install Termux from F-Droid
2. In Termux, run:
   ```bash
   pkg update
   pkg install qemu-system-aarch64-headless qemu-utils
   ```
3. Connect device to computer via USB
4. Run the extraction script (choose option 1)

**Time:** ~15 minutes

### Method B: From Downloaded Packages
**Requirements:**
- Download QEMU .deb packages manually

**Steps:**
1. Go to: https://packages.termux.dev/apt/termux-main/pool/main/
2. Download:
   - `qemu-system-aarch64-headless_*_aarch64.deb`
   - `qemu-utils_*_aarch64.deb`
3. Place in `tools/termux_apk/`
4. Run the extraction script (choose option 2)

**Time:** ~5 minutes (after download)

---

## Alternative: Build QEMU from Source

If you prefer building from source or Termux binaries don't work:

**Requirements:**
- Android NDK
- Build tools (make, gcc, etc.)
- 4-6 hours of time

**See:** [QEMU Build Guide](https://www.qemu.org/download/#source) and Android NDK documentation

This is **not recommended** for most users. Use Termux binaries instead.

---

## Verification

After acquiring assets, verify everything is correct:

```bash
./scripts/verify_assets.sh
```

**This checks:**
- All required files present
- Correct file sizes
- Binary architecture (aarch64)
- File formats (gzip, ELF)

**Expected output:**
```
Errors:   0
Warnings: 0
✅ All assets verified successfully!
```

---

## Generate Checksums

After all assets are in place:

```bash
./scripts/generate_checksums.sh
```

Creates `android/app/src/main/assets/checksums.txt` with SHA-256 hashes.

---

## Current Asset Status

Check what's in place:

```bash
ls -lh android/app/src/main/assets/*/
```

### Expected Final Structure

```
android/app/src/main/assets/
├── qemu/
│   ├── qemu-system-aarch64  (~15-20MB)
│   └── qemu-img            (~2-3MB)
├── vm/
│   └── base.qcow2.gz       (~50MB)
├── bootstrap/
│   ├── api_server.py       (✅ 7.4KB - present)
│   ├── init_bootstrap.sh   (✅ 2.4KB - present)
│   └── requirements.txt    (✅ 49B - present)
└── checksums.txt           (generated after all assets ready)
```

**Total size:** ~65-75MB

---

## Troubleshooting

### "qemu-img not found" when running download_alpine.sh

**Solution:**
```bash
# macOS
brew install qemu

# Ubuntu/Debian
sudo apt-get install qemu-utils

# Fedora
sudo dnf install qemu-img
```

### "adb not found" when extracting from Termux

**Solution:**
Install Android SDK Platform Tools:
- macOS: `brew install android-platform-tools`
- Or download from: https://developer.android.com/tools/releases/platform-tools

### Termux QEMU packages not found

**Solution:**
Make sure you're using F-Droid version of Termux, not Google Play:
- F-Droid: https://f-droid.org/en/packages/com.termux/
- Google Play version is outdated

### Alpine download is too slow

**Solution:**
Try a different mirror. Edit `scripts/download_alpine.sh` and change:
```bash
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
```
to a closer mirror from: https://alpinelinux.org/downloads/

### Binary won't execute on Android device

**Solution:**
- Ensure it's aarch64 architecture (check with `file` command)
- Verify it's from Termux aarch64 packages
- Some devices have SELinux restrictions - test on multiple devices

---

## What Happens Next (Phase 3)

After Phase 2 is complete:
1. Assets will be extracted to app-private storage on first run
2. VmManager will verify checksums
3. QEMU will be launched with proper parameters
4. Alpine Linux will boot and run bootstrap scripts
5. Docker and API server will start inside the VM

---

## Quick Reference Commands

```bash
# Interactive setup
./scripts/setup_assets.sh

# Download Alpine only
./scripts/download_alpine.sh

# Extract QEMU from Termux
./scripts/extract_from_termux.sh

# Copy bootstrap (already done)
./scripts/copy_bootstrap.sh

# Generate checksums
./scripts/generate_checksums.sh

# Verify everything
./scripts/verify_assets.sh

# Show current status
ls -lRh android/app/src/main/assets/
```

---

## Estimated Timeline

### Minimum Path (with existing Termux)
- Copy bootstrap scripts: ✅ Complete
- Download Alpine: ~5-10 minutes
- Extract QEMU from Termux: ~5 minutes
- Generate checksums: ~1 minute

**Total: ~15-20 minutes**

### Full Path (from scratch)
- Set up Termux on device: ~10 minutes
- Install QEMU in Termux: ~10 minutes
- Copy bootstrap scripts: ✅ Complete
- Download Alpine: ~5-10 minutes
- Extract QEMU: ~5 minutes
- Generate checksums: ~1 minute

**Total: ~30-40 minutes**

---

## Need Help?

1. Check `ASSET_GUIDE.md` for detailed manual instructions
2. Check script output for specific error messages
3. Run `./scripts/verify_assets.sh` to see what's missing
4. Ensure all dependencies are installed (qemu-img, adb, etc.)

---

## Next Phase Preview

**Phase 3: Native VM Manager Implementation**

Once assets are ready, we'll implement:
- Asset extraction to app-private storage
- Checksum verification
- QEMU process launching
- PID tracking and health monitoring
- User QCOW2 overlay creation

Estimated time: 2-3 hours of development
