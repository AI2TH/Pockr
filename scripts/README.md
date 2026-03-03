# Scripts

> **Rule: Docker only.** Every download, build, and test runs inside a Docker container.
> The only tool required on the host is **Docker Desktop**.

---

## Active scripts

| Script | What it does | When to run |
|---|---|---|
| `build_apk.sh` | Builds the Flutter Android APK inside an Ubuntu/JDK/Flutter Docker container | Every code change |
| `build_alpine_base.sh` | Builds the Alpine base QCOW2 image (Docker + Python pre-installed) | When `guest/` files change |
| `alpine_build_inner.sh` | Inner build logic invoked by `build_alpine_base.sh` inside the Alpine container | Called automatically — do not run directly |
| `firebase_test.sh` | Submits APK to Firebase Test Lab for Robo test on Pixel2.arm (Android 11) | After each APK build |

---

## `build_apk.sh`

```bash
./scripts/build_apk.sh          # debug build (default)
./scripts/build_apk.sh release  # release build
```

Builds a `docker-app-builder` Docker image (Ubuntu 22.04 + JDK 17 + Android SDK + Flutter 3.22.2) on first run (~10 min), then runs the Flutter build inside it.

**Output:** `build/docker-vm-debug.apk` or `build/docker-vm-release.apk` (~220 MB debug)

**Builder image is cached** — subsequent builds take ~2–3 minutes.

---

## `build_alpine_base.sh`

```bash
./scripts/build_alpine_base.sh
```

Builds a custom Alpine Linux 3.19 (aarch64) root filesystem with:
- Docker CE pre-installed and configured (iptables=false, bridge=none for virt kernel)
- Python 3 + FastAPI + uvicorn + pydantic pre-installed
- `api_server.py`, `init_bootstrap.sh` baked in from `guest/`
- DNS configured with fallback servers and `options use-vc` (TCP-forced DNS)
- Converts to QCOW2 and gzips the result

**Output:** `android/app/src/main/assets/vm/base.qcow2.gz` (~102 MB)

**Re-run when:** `guest/api_server.py`, `guest/init_bootstrap.sh`, or `guest/requirements.txt` change.

After rebuilding the base image, also bump the extraction marker in `VmManager.kt`:
```kotlin
// Change the version suffix in assetsReady() and extractAssets():
File(filesDir, "assets_extracted.vN")  // increment N
```

---

## `firebase_test.sh`

```bash
./scripts/firebase_test.sh docker-28f14 Pixel2.arm 30
```

Arguments: `<project-id> <device-model> <android-api-level>`

Requires `service-account-key.json` in the project root (Firebase service account, gitignored).

**Test device:** Pixel2.arm — ARM64 physical device, Android 11 (API 30)
**GCS bucket:** `test-lab-a6uqmcd6pp4xs-yxka23mkk7jy8`

Download logcat after test:
```bash
gsutil cp "gs://test-lab-a6uqmcd6pp4xs-yxka23mkk7jy8/<run-id>/Pixel2.arm-30-en-portrait/logcat" /tmp/logcat.txt
```

---

## Legacy scripts (not part of current workflow)

These scripts were used during initial setup. QEMU binaries are now committed in `jniLibs/` and the base image is built via `build_alpine_base.sh`, so these are no longer needed for normal development.

| Script | Original purpose |
|---|---|
| `download_alpine.sh` | Download Alpine ISO and convert to QCOW2 |
| `extract_from_termux.sh` | Extract QEMU binaries from Termux `.deb` packages |
| `build_qemu.sh` | Cross-compile QEMU from source for Android ARM64 |
| `setup_assets.sh` | Interactive menu for the above scripts |
| `copy_bootstrap.sh` | Copy `guest/` scripts into `assets/bootstrap/` |
| `verify_assets.sh` | Validate assets before APK build |
| `generate_checksums.sh` | SHA-256 checksums for assets |
| `test_api.sh` | Test `api_server.py` end-to-end with Docker-in-Docker |

---

## Asset locations

```
android/app/src/main/
├── jniLibs/arm64-v8a/      QEMU + ~50 shared libs (committed to git)
│   ├── libqemu.so           qemu-system-aarch64
│   ├── libqemu_img.so       qemu-img
│   └── lib*.so (×48)        glib, zlib, gnutls, etc.
└── assets/
    ├── vm/
    │   ├── base.qcow2.gz    ← from build_alpine_base.sh  (not committed)
    │   ├── vmlinuz-virt     ← committed
    │   └── initramfs-virt   ← committed
    └── bootstrap/
        ├── api_server.py    ← from guest/  (committed)
        ├── init_bootstrap.sh
        └── requirements.txt
```
