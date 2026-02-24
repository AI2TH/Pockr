# Asset & Build Scripts

> **Rule: Docker only.** Every download, build, and test runs inside a Docker container.
> The only tool required on the host is **Docker Desktop**.

---

## Scripts

| Script | What it does | Docker image used |
|---|---|---|
| `setup_assets.sh` | Interactive menu — entry point for everything | delegates |
| `copy_bootstrap.sh` | Copies `guest/` scripts into Android assets | `alpine:3.19` |
| `download_alpine.sh` | Downloads Alpine ISO, converts to `base.qcow2.gz` | `debian:bookworm-slim` |
| `extract_from_termux.sh` | Extracts QEMU binaries from Termux `.deb` packages | `debian:bookworm-slim` |
| `build_qemu.sh` | Cross-compiles QEMU for Android ARM64 from source | `debian:bookworm` |
| `generate_checksums.sh` | SHA-256 checksums for all assets | `alpine:3.19` |
| `verify_assets.sh` | Validates all assets before APK build | `debian:bookworm-slim` |
| `test_api.sh` | Tests the guest API server end-to-end | `docker:dind` + `alpine:3.19` |

---

## Quick start

```bash
# Interactive menu — start here
./scripts/setup_assets.sh
```

Choose **option 5 (Full setup)** which runs:
1. Copy bootstrap scripts
2. Download Alpine image (~50 MB)
3. Get QEMU binaries (Termux `.deb` or build from source)

Then verify:
```bash
./scripts/verify_assets.sh
```

---

## Individual scripts

### `copy_bootstrap.sh`
```bash
./scripts/copy_bootstrap.sh
```
Copies `guest/api_server.py`, `init_bootstrap.sh`, `requirements.txt` into
`android/app/src/main/assets/bootstrap/`. Run this after editing guest files.

### `download_alpine.sh`
```bash
./scripts/download_alpine.sh
```
Downloads Alpine Linux 3.19.1 (aarch64) ISO inside Docker, converts to QCOW2,
compresses with gzip -9, and places `base.qcow2.gz` in `android/app/src/main/assets/vm/`.

### `extract_from_termux.sh`
```bash
./scripts/extract_from_termux.sh
```
Two options:
- **Option 1 — adb pull** (fastest): requires an Android device with Termux installed
  and `qemu-system-aarch64-headless` + `qemu-utils` packages. adb runs on the host.
- **Option 2 — .deb extraction** (fully Docker): download `.deb` files from
  `https://packages.termux.dev/apt/termux-main/pool/main/` into `tools/termux_packages/`,
  then the script extracts binaries inside `debian:bookworm-slim`.

### `build_qemu.sh`
```bash
./scripts/build_qemu.sh
# or specify version:
QEMU_VERSION=8.2.0 ./scripts/build_qemu.sh
```
Cross-compiles QEMU from source inside `debian:bookworm` targeting `aarch64-linux`.
Takes ~20–30 minutes. Use this if you don't have Termux or `.deb` files.

### `generate_checksums.sh`
```bash
./scripts/generate_checksums.sh
```
Generates `android/app/src/main/assets/checksums.txt` (SHA-256 of all assets).
Run after all assets are in place.

### `verify_assets.sh`
```bash
./scripts/verify_assets.sh
```
Validates binary type, file sizes, format, and checksums inside Docker.
Run before building the APK.

### `test_api.sh`
```bash
./scripts/test_api.sh
```
Starts the guest API server inside a Docker-in-Docker container with a real Docker
daemon, then runs automated HTTP tests against all endpoints. Use this to validate
`guest/api_server.py` changes without a physical Android device.

---

## Output directories

```
android/app/src/main/assets/
├── qemu/
│   ├── qemu-system-aarch64   ← from extract_from_termux.sh or build_qemu.sh
│   └── qemu-img              ← same
├── vm/
│   └── base.qcow2.gz         ← from download_alpine.sh
├── bootstrap/
│   ├── api_server.py         ← from copy_bootstrap.sh
│   ├── init_bootstrap.sh     ← from copy_bootstrap.sh
│   └── requirements.txt      ← from copy_bootstrap.sh
└── checksums.txt             ← from generate_checksums.sh

tools/
├── downloads/                ← Alpine ISO + QCOW2 (intermediate, not committed)
└── termux_packages/          ← Termux .deb files (not committed)
```

---

## Requirements

**Host:** Docker Desktop only.
**No** wget, curl, qemu-img, ar, dpkg, shasum, file, gzip required on the host.
