# Quick Setup Guide

Get the Docker VM app running in 3 steps. **Docker Desktop is the only host requirement** — no Homebrew, no Android SDK, no Flutter, no QEMU.

---

## Prerequisites

- macOS or Linux with **Docker Desktop** installed and running
- Android device: ARM64, Android 8.0+ (API 26+), ~250 MB free storage, ~2–3 GB free RAM
- USB cable with USB debugging enabled (for `adb install`)

---

## Step 1 — Build the Alpine base image

The base image is Alpine Linux with Docker + Python pre-installed. It's baked into the APK as a compressed QCOW2 asset.

```bash
./scripts/build_alpine_base.sh
```

- Runs entirely inside Docker (no host tools needed)
- Takes ~10–15 minutes on first run
- Output: `android/app/src/main/assets/vm/base.qcow2.gz` (~102 MB)

> **Re-run only when** `guest/api_server.py`, `guest/init_bootstrap.sh`, or `guest/requirements.txt` change.
> QEMU binaries and the kernel/initrd are already committed in the repo — no extra acquisition step.

---

## Step 2 — Build the APK

```bash
./scripts/build_apk.sh
# Output: build/docker-vm-debug.apk (~220 MB)
```

- Runs entirely inside Docker — builds a Ubuntu/JDK/Android SDK/Flutter environment on first run (~10 min)
- Subsequent builds reuse the cached builder image (~2–3 min)

For a release build:

```bash
./scripts/build_apk.sh release
# Output: build/docker-vm-release.apk
```

---

## Step 3 — Install and run

```bash
adb install -r build/docker-vm-debug.apk
```

Or transfer the APK manually to the device and install it.

**First launch:**

1. Tap **Start VM** on the dashboard
2. Assets extract to app-private storage (~10–30 s)
3. QEMU boots Alpine Linux (~30–60 s)
4. Very first boot: `init_bootstrap.sh` installs Docker inside the VM (~5–10 min)
5. Dashboard shows **RUNNING** — containers are ready to use

**Subsequent launches:** ~30–60 s boot time. Previously pulled Docker images are available immediately.

---

## Troubleshooting

**VM won't start / stays at "Starting"**

```bash
adb logcat | grep -E "VmManager|QEMU|VmService"
```

Common causes:
- Not enough RAM on device (need ~2 GB free)
- First-boot Docker installation still in progress (wait up to 10 min)

**Health check never passes**

- Check that `api_server.py` is listening on `0.0.0.0:7080` (not `127.0.0.1`)
- Verify the token is being passed correctly via kernel cmdline

**`docker pull` fails inside VM**

The VM's `/etc/resolv.conf` must include fallback DNS and `options use-vc`. If the base image was built before this fix, rebuild with `./scripts/build_alpine_base.sh`.

**Build fails with "APK not found"**

Run with full output to see the actual Gradle/Dart error:

```bash
# Temporarily edit scripts/build_apk.sh line 120:
# Change:  | tail -50
# To:      | tee /tmp/flutter_build.log | tail -50
# Then:
grep -i "error" /tmp/flutter_build.log | head -20
```

---

## Firebase Test Lab

Run automated Robo tests on real ARM64 hardware without a physical device:

```bash
./scripts/firebase_test.sh docker-28f14 Pixel2.arm 30
```

Requires `service-account-key.json` (Firebase service account, gitignored).

---

## Timing reference

| Step | First time | Repeat |
|---|---|---|
| Build Alpine base image | ~10–15 min | ~5 min (Docker cache) |
| Build APK (builder image first time) | ~10 min | ~2–3 min |
| VM boot | ~30–60 s | ~30–60 s |
| First Docker install in VM | ~5–10 min | skipped (persistent overlay) |
| Docker image pull (e.g. nginx) | ~30–120 s | instant (cached) |

---

## Minimum device specs

| Requirement | Minimum | Recommended |
|---|---|---|
| Android version | 8.0 (API 26) | 10+ (API 29+) |
| Architecture | ARM64 (aarch64) | ARM64 |
| Free RAM | 2 GB | 3–4 GB |
| Free storage | 250 MB (APK) | 1 GB+ |
