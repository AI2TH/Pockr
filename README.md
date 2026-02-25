# docker-on-android

Run Docker containers on a non-rooted Android device — no Termux, no root, one APK.

The app embeds a QEMU virtual machine running Alpine Linux. Docker runs inside the VM. A FastAPI server inside the VM exposes a REST API over localhost, which the Flutter UI calls to manage containers.

---

## How it works

```
Android App (Flutter + Kotlin)
  └── VmManager  ──launches──▶  QEMU (qemu-system-aarch64)
                                  └── Alpine Linux VM
                                        └── Docker daemon
                                        └── API server (FastAPI :7080)
  └── VmApiClient ──HTTP──▶  http://127.0.0.1:7080  (hostfwd)
```

- **No root required** — QEMU user-mode networking (slirp) works as a regular app
- **No Termux** — QEMU binaries and Alpine image are bundled inside the APK
- **Token auth** — UUID token injected into the VM via QEMU `fw_cfg`, validated on every API call

---

## Features

- Start / stop the embedded Linux VM from the app
- Pull Docker images and run containers
- View real-time container logs
- Start/stop containers from the UI
- Configurable vCPU count and RAM (1–4 cores, 512 MB–4 GB)
- Persistent notification while VM is running (ForegroundService)

---

## Requirements

### Host (development machine)
- **Docker Desktop** — the only requirement; everything else runs inside Docker

### Device
- Android 8.0+ (API 26+)
- ARM64 (aarch64) device
- ~1 GB free storage (APK ~465 MB including QEMU + Alpine image)
- ~2–3 GB free RAM recommended while VM is running

---

## Project structure

```
docker-on-android/
├── lib/                        Flutter UI (Dart)
│   ├── main.dart
│   ├── screens/
│   │   ├── dashboard.dart      VM status, start/stop
│   │   ├── containers.dart     Container list, logs
│   │   └── settings.dart       vCPU / RAM sliders
│   └── services/
│       └── vm_platform.dart    MethodChannel + VmState
│
├── android/                    Android native (Kotlin)
│   └── app/src/main/
│       ├── kotlin/com/example/dockerapp/
│       │   ├── MainActivity.kt     MethodChannel handler
│       │   ├── VmManager.kt        Asset extraction + QEMU launch
│       │   ├── VmApiClient.kt      HTTP client (auth token)
│       │   └── VmService.kt        ForegroundService
│       └── assets/
│           ├── qemu/               qemu-system-aarch64, qemu-img
│           ├── vm/                 base.qcow2.gz (Alpine Linux)
│           └── bootstrap/          api_server.py, init_bootstrap.sh
│
├── guest/                      Files that run inside the VM
│   ├── api_server.py           FastAPI server (Docker management)
│   ├── init_bootstrap.sh       First-boot setup (installs Docker)
│   └── requirements.txt
│
├── docker/
│   └── Dockerfile.build        Ubuntu → JDK 17 → Android SDK → Flutter
│
└── scripts/
    ├── build_apk.sh            Build APK inside Docker
    ├── build_qemu.sh           Build QEMU for Android ARM64 inside Docker
    ├── download_alpine.sh      Download + convert Alpine ISO inside Docker
    ├── copy_bootstrap.sh       Sync guest/ scripts into assets/
    ├── verify_assets.sh        Validate all assets before building
    ├── generate_checksums.sh   SHA-256 checksums for assets
    ├── test_api.sh             Test guest API server with Docker-in-Docker
    └── setup_assets.sh         Interactive menu for all of the above
```

---

## Getting started

### 1. Clone

```bash
git clone https://github.com/ai2th/docker-on-android.git
cd docker-on-android
```

### 2. Acquire assets

All steps run inside Docker — no other tools needed on the host.

```bash
# Interactive menu
./scripts/setup_assets.sh
```

Or run individually:

```bash
# Bootstrap scripts (guest/ → assets/bootstrap/)
./scripts/copy_bootstrap.sh

# Alpine Linux image (~50 MB download, converts to QCOW2 inside Docker)
./scripts/download_alpine.sh

# QEMU binaries — choose one:
./scripts/extract_from_termux.sh   # fast: pull from Termux .deb packages
./scripts/build_qemu.sh            # from source inside Docker (~20 min)

# Verify everything is in place
./scripts/verify_assets.sh
```

### 3. Build APK

```bash
./scripts/build_apk.sh
# Output: build/docker-vm-debug.apk (~465 MB)
```

First build takes ~25 minutes (downloads JDK + Android SDK + Flutter inside Ubuntu). Subsequent builds reuse cached Docker layers.

### 4. Install

```bash
adb install -r build/docker-vm-debug.apk
```

Or transfer the APK manually and install it on the device.

---

## First run

1. Open the app → tap **Start VM**
2. Assets are extracted to app-private storage on first launch (~30 seconds)
3. QEMU boots Alpine Linux (~2–3 minutes)
4. `init_bootstrap.sh` runs inside the VM — installs Docker and starts the API server (~5–10 minutes on very first boot)
5. Once the API health check passes, the dashboard shows **RUNNING** and containers can be managed

> First boot is slow because Docker is installed from Alpine packages inside the VM. Subsequent boots take ~30–60 seconds.

---

## Docker Hub

Pre-built images are published to Docker Hub under `ai2th`:

| Image | Description |
|---|---|
| `ai2th/ubuntu:22.04` | Ubuntu base used for APK builds |
| `ai2th/qemu-android:8.2.0` | QEMU 8.2.0 binaries built for Android ARM64 |

Pull QEMU binaries from Docker Hub instead of building from source:

```bash
docker run --rm \
  -v "$(pwd)/android/app/src/main/assets/qemu:/out" \
  ai2th/qemu-android:8.2.0 \
  bash -c 'cp /qemu-android/* /out/'
```

---

## Architecture notes

### Why a VM?

Stock Android kernels disable `CONFIG_USER_NS` (required for Docker rootless mode) and restrict cgroup access for regular apps. A QEMU VM provides a complete Linux environment with its own kernel — Docker runs normally inside it.

Reference: [android.googlesource.com/kernel/common — gki_defconfig](https://android.googlesource.com/kernel/common/+/refs/heads/android-mainline/arch/arm64/configs/gki_defconfig)

### Networking

QEMU uses slirp user-mode networking (no root required):

- `hostfwd=tcp::7080-:7080` exposes the guest API server to Android localhost
- Guest is not directly reachable from outside — only via hostfwd ports
- ICMP/ping does not work inside the guest (slirp limitation)
- Performance is lower than tap/bridge networking

### Token auth

A UUID token is generated on first app launch and stored in `vm_app_prefs`. It is injected into the VM via:

```
qemu-system-aarch64 ... -fw_cfg name=opt/api_token,string=<TOKEN>
```

The guest reads it from `/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw`. Every API request must include `Authorization: Bearer <token>`.

### Settings

vCPU count and RAM are stored in Flutter `SharedPreferences` (`FlutterSharedPreferences`, keys `flutter.vcpu_count` and `flutter.ram_mb`). `VmManager.kt` reads them before launching QEMU.

---

## Guest API

All endpoints except `/health` require `Authorization: Bearer <token>`.

| Method | Path | Body / Query | Description |
|---|---|---|---|
| GET | `/health` | — | `{"status","runtime","version"}` |
| GET | `/containers` | — | List running containers |
| POST | `/containers/start` | `{"image","name","cmd","env","ports"}` | Run a container |
| POST | `/containers/stop` | `{"name"}` | Stop a container |
| GET | `/logs` | `?name=&tail=` | Container logs |
| POST | `/images/pull` | `{"image"}` | Pull an image |
| POST | `/exec` | `{"name","cmd"}` | Exec in a container |

---

## Testing the API

Test the guest API server end-to-end using Docker-in-Docker (no Android device needed):

```bash
./scripts/test_api.sh
```

Starts a real Docker daemon inside a container, starts the API server, runs HTTP tests against all endpoints, and reports PASS/FAIL.

---

## Docs

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — primary design document
- [`ARCHITECTURE2.md`](ARCHITECTURE2.md) — companion reference
- [`ARC_START.md`](ARC_START.md) — phased MVP plan
- [`ASSET_GUIDE.md`](ASSET_GUIDE.md) — asset acquisition guide
- [`scripts/README.md`](scripts/README.md) — script reference

---

## Licensing

| Component | License |
|---|---|
| QEMU | GPLv2 (TCG: BSD/Expat) |
| Alpine Linux | MIT / various |
| Docker | Apache 2.0 |
| Flutter | BSD 3-Clause |

QEMU source or written offer is available per GPLv2 §3. Third-party notices are accessible in the app under **Settings → About**.

References: [wiki.qemu.org/License](https://wiki.qemu.org/License)

---

## Related

- [termux-docker-no-root](https://github.com/mabdulmoghni/termux-docker-no-root) — community validation of the VM-based approach this project is based on
