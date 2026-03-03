# docker-on-android — Issues, Context & Progress Log

## Project Goal
Single APK that runs Docker containers on a non-rooted Android device using QEMU + Alpine Linux VM. No Termux, no root.

## Architecture
```
Flutter UI → MethodChannel → VmManager.kt → ProcessBuilder(libqemu.so) → Alpine VM → Docker daemon
                                           → libqemu_img.so (create user.qcow2 overlay)
```

---

## Issues Encountered & Resolutions

### 1. QEMU binary — Permission Denied (SELinux)
**Error:** `Cannot run program "files/qemu/qemu-system-aarch64": error=13, Permission denied`
**Cause:** Android 10+ blocks `execve()` from `getFilesDir()` via SELinux W^X policy.
**Fix:** Moved QEMU binaries to `jniLibs/arm64-v8a/` as `.so` files. Android installs them to `nativeLibraryDir` which has `exec_type` SELinux label. ✅

### 2. jniLibs not extracted to disk (useLegacyPackaging)
**Error:** `libqemu.so not found in nativeLibraryDir`
**Cause:** AGP 3.6+ stores native libs compressed inside APK by default — not extracted to disk.
**Fix:** Added `packagingOptions { jniLibs { useLegacyPackaging true } }` to `build.gradle`. ✅

### 3. Wrong ELF interpreter — Android rejects binary
**Error:** `libqemu.so` silently not extracted during install.
**Cause:** Self-built QEMU from Debian had interpreter `/lib/ld-linux-aarch64.so.1` (glibc). Android only extracts `.so` files with interpreter `/system/bin/linker64` (Bionic).
**Fix:** Switched to Termux pre-built QEMU binaries which use Android's linker64. ✅

### 4. Missing shared library dependencies (chained)
**Errors (in order):**
- `library "libzstd.so.1" not found` → added libzstd
- `library "libssh.so" not found` → added libssh (from Termux `libssh` package)
- `library "libbz2.so" not found` → added libbz2 (from Termux `libbz2` package, separate from `bzip2`)
- `library "libandroid-support.so" not found` → added libandroid-support (Termux POSIX shim)
- `library "libpcre2-8.so" not found` → added pcre2 family
- `library "libnghttp3.so" not found` → added libnghttp3
- `library "libnghttp2.so" not found` → added libnghttp2
- `library "libngtcp2_crypto_ossl.so" not found` → added libngtcp2 family
- libgnutls, libtasn1, libnettle, libhogweed, libgmp, libevent family
**Root cause:** All Termux packages depend on Termux's own `/data/data/com.termux/files/usr/lib/` which doesn't exist on non-Termux devices.
**Fix:** Extract all Termux `.deb` dependencies and bundle them in `jniLibs/arm64-v8a/`. Rename versioned sonames (e.g., `libzstd.so.1.5.7` → `libzstd.so`) using `patchelf --set-soname`. ✅

### 5. Termux RUNPATH pointing to nonexistent path
**Error:** `cannot locate symbol "ssh_init" referenced by libqemu_img.so` — even though libssh.so was present.
**Cause:** All Termux binaries embed `RUNPATH=/data/data/com.termux/files/usr/lib` in their ELF. Android's linker tries this RUNPATH first for symbol resolution. Path doesn't exist → symbols not found.
**Fix:** `patchelf --remove-rpath` on ALL 49 jniLibs. ✅

### 6. Long→Int cast exception (Flutter SharedPreferences)
**Error:** `java.lang.Long cannot be cast to java.lang.Integer`
**Cause:** Flutter's SharedPreferences plugin stores integers as `Long` on Android, but `VmManager.kt` was calling `getInt()` which throws ClassCastException.
**Fix:** Added `getFlutterInt()` helper that catches ClassCastException and falls back to `getLong().toInt()`. ✅

### 7. gnutls_cipher_init symbol not found (namespace isolation)
**Error:** `cannot locate symbol "gnutls_cipher_init" referenced by libqemu_img.so`
**Cause:** Android 7+ enforces linker namespace isolation. Even though `libgnutls.so` is loaded (transitively via libcurl), its symbols are NOT visible to `libqemu_img.so` unless `libgnutls.so` is in `libqemu_img.so`'s direct NEEDED list.
**Current approach:** Adding minimal set of required libs to NEEDED via symbol analysis.

### 8. ELF corruption from too many NEEDED entries
**Error:** `bionic/linker/linker_phdr.cpp:168: Load CHECK 'did_read_' failed` (SIGABRT)
**Cause:** Adding ALL 50 jniLibs to NEEDED via patchelf exceeded patchelf's safe limits and corrupted the ELF program headers.
**Fix in progress:** Re-download fresh `libqemu_img.so` from Termux, then surgically add only the minimal set of libs that directly provide undefined symbols.

---

## Asset Issues

### 9. base.qcow2.gz renamed by aapt2
**Issue:** Put `base.qcow2.gz` in `assets/vm/`. aapt2 decompressed it and stored as `base.qcow2` (without .gz extension).
**Fix:** Code tries `vm/base.qcow2` first, then falls back to `vm/base.qcow2.gz`. ✅

### 10. APK signature changes on each build (INSTALL_FAILED_UPDATE_INCOMPATIBLE)
**Issue:** Each Gradle debug build uses a different random key. `adb install -r` fails with signature mismatch.
**Fix:** Added `android/app/debug.keystore` (committed) and configured `signingConfigs.debug` to always use it. ✅

### 11. MIUI blocking ADB install
**Device:** POCO M4 Pro (MIUI V816)
**Issue:** `INSTALL_FAILED_USER_RESTRICTED` — MIUI blocks `adb install` without "Install via USB" enabled.
**Workaround:** `adb push <apk> /data/local/tmp/app.apk && adb shell pm install -r /data/local/tmp/app.apk` ✅

---

## Infrastructure Issues

### 12. Android Emulator in Docker not working on Apple Silicon
**Issue:** `budtmo/docker-android` is x86_64 only. On ARM64 Apple Silicon + Colima QEMU, nested x86_64 emulation crashes (SIGSEGV in emulator).
**Cause:** Android emulator requires hardware virtualization (KVM), which is not available through nested QEMU emulation.
**Resolution:** Use Firebase Test Lab (cloud real devices) for automated testing. ✅

### 13. OOM during Flutter/Gradle build
**Issue:** Kotlin daemon killed (SIGABRT exit 134) during APK compilation.
**Cause:** Colima VM had only 1.91 GB RAM; Flutter tool compilation needs ~4 GB.
**Fix:** Restarted Colima with `--memory 12` (12 GB). Also tuned `gradle.properties`: `org.gradle.jvmargs=-Xmx2g`, `kotlin.daemon.jvm.options=-Xmx1g`. ✅

### 14. Colima context switching
**Issue:** Multiple Colima restarts needed to change VM type (QEMU → VZ → QEMU) require `colima delete` first.
**Note:** VZ mode provides better x86_64 Rosetta support but no KVM for Android emulator.

---

## Firebase Test Lab Setup
- **Project:** `docker-28f14`
- **GCP Project:** `my-project1-366819`
- **Service account:** `docker@my-project1-366819.iam.gserviceaccount.com`
- **Test device:** `Pixel2.arm` (ARM virtual device, Android 30)
- **Script:** `scripts/firebase_test.sh`

### Test history
| Run | Result | Issue found |
|---|---|---|
| 1 | Passed | UI crawl only (no Start VM tap) |
| 2 | Passed | New dark UI rendering correctly; Long→Int error shown |
| 3 | Passed | Long→Int fixed; gnutls_cipher_init missing |
| 4 | Failed (CRASH) | ELF corruption from too many NEEDED entries |

---

## Current Status (2026-02-27)

| Component | Status |
|---|---|
| Flutter UI (dark theme) | ✅ Working |
| Asset extraction (qcow2, bootstrap) | ✅ Working |
| jniLibs extraction to nativeLibraryDir | ✅ Working |
| Termux RUNPATH removed | ✅ Fixed |
| Long→Int SharedPrefs cast | ✅ Fixed |
| libqemu_img.so symbol resolution | 🔄 In progress (namespace isolation fix) |
| qemu-img create user.qcow2 | ⏳ Blocked on above |
| QEMU VM boot | ⏳ Blocked on above |
| Alpine Linux first boot | ⏳ Pending |
| Docker daemon start | ⏳ Pending |
| API server response | ⏳ Pending |

---

## Key File Locations
- `android/app/src/main/jniLibs/arm64-v8a/` — 50 Termux libs (QEMU + all deps)
- `android/app/src/main/assets/vm/base.qcow2` — Alpine Linux QCOW2 (70 MB, decompressed by aapt2)
- `android/app/src/main/assets/bootstrap/` — api_server.py, init_bootstrap.sh
- `android/app/src/main/kotlin/com/example/dockerapp/VmManager.kt` — core VM logic
- `scripts/firebase_test.sh` — Firebase Test Lab runner (Docker-based)
- `scripts/build_apk.sh` — APK builder (Docker-based, Ubuntu:22.04)
- `service-account-key.json` — Firebase service account (NOT committed, in project root)

---

## Dependencies Stack
```
libqemu_img.so (Termux QEMU 10.2.1, ARM64, /system/bin/linker64)
  └── libcurl.so → libssl.so, libcrypto.so (OpenSSL), libnghttp2, libnghttp3,
      libngtcp2, libngtcp2_crypto_ossl, libssh.so, libssh2.so, libgnutls.so,
      libidn2.so, libunistring.so, libz.so, libzstd.so
  └── libglib-2.0.so → libpcre2-8.so, libffi.so, libiconv.so, libandroid-support.so
  └── libbz2.so (from Termux libbz2 package)
  └── [48 more Termux libs in jniLibs]
```
