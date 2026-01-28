# Asset Acquisition Scripts

Automation scripts for Phase 2 asset acquisition.

## Scripts Overview

### 🎯 setup_assets.sh
**Master script with interactive menu**

Run this first. It provides options for:
1. Copy bootstrap scripts only
2. Download Alpine Linux
3. Extract QEMU from Termux
4. Full automated setup
5. Generate checksums
6. Verify all assets

```bash
./scripts/setup_assets.sh
```

### 📥 download_alpine.sh
**Download and prepare Alpine Linux image**

- Downloads Alpine Linux 3.19.1 aarch64 ISO
- Converts to QCOW2 format
- Compresses to base.qcow2.gz
- Places in assets/vm/

**Requirements:** qemu-img, wget/curl

```bash
./scripts/download_alpine.sh
```

### 📱 extract_from_termux.sh
**Extract QEMU binaries from Termux**

Two modes:
1. From device via adb
2. From downloaded .deb packages

**Requirements:** adb (for option 1) or dpkg-deb/ar (for option 2)

```bash
./scripts/extract_from_termux.sh
```

### 📋 copy_bootstrap.sh
**Copy bootstrap scripts to assets**

Copies guest scripts to Android assets:
- api_server.py
- init_bootstrap.sh
- requirements.txt

```bash
./scripts/copy_bootstrap.sh
```

### 🔐 generate_checksums.sh
**Generate SHA-256 checksums**

Creates checksums.txt for all assets.

Run this after all assets are in place.

```bash
./scripts/generate_checksums.sh
```

### ✅ verify_assets.sh
**Verify all assets are present and valid**

Checks:
- File existence
- File sizes
- Binary architecture
- File formats

```bash
./scripts/verify_assets.sh
```

## Usage Flow

### Quick Flow (Recommended)
```bash
# 1. Interactive setup
./scripts/setup_assets.sh
# Choose option 4 (Full automated setup)

# 2. Extract QEMU (manual or via Termux)
./scripts/extract_from_termux.sh

# 3. Verify
./scripts/verify_assets.sh
```

### Manual Flow
```bash
# 1. Copy bootstrap
./scripts/copy_bootstrap.sh

# 2. Download Alpine
./scripts/download_alpine.sh

# 3. Extract QEMU
./scripts/extract_from_termux.sh

# 4. Generate checksums
./scripts/generate_checksums.sh

# 5. Verify
./scripts/verify_assets.sh
```

## Script Outputs

All scripts create/modify files in:
```
android/app/src/main/assets/
├── qemu/              # QEMU binaries
├── vm/                # Alpine Linux image
├── bootstrap/         # Bootstrap scripts
└── checksums.txt      # SHA-256 hashes
```

Temporary downloads go to:
```
tools/downloads/       # Alpine ISO, QCOW2
tools/termux_apk/      # Termux .deb packages
```

## Error Handling

All scripts:
- Check for required tools before running
- Provide clear error messages
- Exit with non-zero status on failure
- Support both macOS and Linux

## Requirements

**All scripts:**
- bash 4.0+
- file, shasum, gzip

**download_alpine.sh:**
- qemu-img
- wget or curl

**extract_from_termux.sh:**
- adb (option 1) or dpkg-deb/ar (option 2)

**verify_assets.sh:**
- file command

## Exit Codes

- `0`: Success
- `1`: Error (missing files, tools, or validation failure)

## Logs

Scripts output to stdout/stderr.

For debugging, run with bash -x:
```bash
bash -x ./scripts/download_alpine.sh
```
