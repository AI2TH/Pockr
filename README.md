# Pockr — Docker on Android

Run Docker containers on a non-rooted Android device — no Termux, no root, one APK.

## Download

**[Download APK (Google Drive)](https://drive.google.com/drive/folders/1LWLATGacL_hoWuJ4V6S4hUEbBOqTci11?usp=drive_link)**

The app embeds QEMU running Alpine Linux. Docker runs inside the VM. A FastAPI server inside the VM exposes a REST API over localhost, which the Flutter UI calls to manage containers.

---

## How it works

```
Android App (Flutter + Kotlin)
  └── VmManager  ──launches──▶  QEMU (libqemu.so from nativeLibraryDir)
                                  └── Alpine Linux VM
                                        └── Docker daemon
                                        └── API server (FastAPI :7080)
  └── VmApiClient ──HTTP──▶  http://127.0.0.1:7080  (QEMU hostfwd)
```

- **No root required** — QEMU user-mode networking (SLIRP) works as a regular app
- **No Termux** — QEMU binaries ship as `jniLibs` inside the APK; Alpine image is a bundled asset
- **Token auth** — UUID token injected into the VM via QEMU kernel cmdline `api_token=<UUID>`; guest reads it from `/proc/cmdline`

---

## Features

- Start / stop the embedded Linux VM
- Pull Docker images and run containers (image is cached across VM restarts)
- View real-time container logs
- Start / stop containers from the UI
- **Terminal** — shell access directly into the Alpine VM host
- Configurable vCPU count and RAM (1–4 cores, 512 MB–4 GB)
- Persistent notification while VM is running (ForegroundService)

---

## Requirements

### Host (development machine)
- **Docker Desktop** — the only requirement; everything else runs inside Docker

### Device
- Android 8.0+ (API 26+)
- ARM64 (aarch64) — only arm64-v8a QEMU binaries are included
- ~250 MB free storage for the APK
- ~2–3 GB free RAM while VM is running

---

## Project structure

```
docker-app/
├── lib/                        Flutter UI (Dart)
│   ├── main.dart               4 tabs: Dashboard, Containers, Terminal, Settings
│   ├── screens/
│   │   ├── dashboard.dart      VM status, start/stop
│   │   ├── containers.dart     Container list, logs
│   │   ├── terminal.dart       VM shell terminal
│   │   └── settings.dart       vCPU / RAM sliders
│   └── services/
│       └── vm_platform.dart    MethodChannel + VmState (health polling)
│
├── android/                    Android native (Kotlin)
│   └── app/src/main/
│       ├── kotlin/com/example/dockerapp/
│       │   ├── DockerApp.kt        Application singleton (holds VmManager)
│       │   ├── MainActivity.kt     MethodChannel handler
│       │   ├── VmManager.kt        Asset extraction + QEMU launch
│       │   ├── VmApiClient.kt      HTTP client (auth token)
│       │   └── VmService.kt        ForegroundService
│       ├── jniLibs/arm64-v8a/  QEMU + ~50 shared libs (committed to git)
│       │   ├── libqemu.so          qemu-system-aarch64
│       │   ├── libqemu_img.so      qemu-img
│       │   └── lib*.so (×48)       shared dependencies (glib, zlib, etc.)
│       └── assets/
│           ├── vm/                 base.qcow2.gz, vmlinuz-virt, initramfs-virt
│           └── bootstrap/          api_server.py, init_bootstrap.sh, requirements.txt
│
├── guest/                      Source files baked into the Alpine base image
│   ├── api_server.py           FastAPI server (Docker + VM shell management)
│   ├── init_bootstrap.sh       First-boot setup script
│   └── requirements.txt
│
├── docker/
│   └── Dockerfile.build        Ubuntu → JDK 17 → Android SDK → Flutter 3.22.2
│
└── scripts/
    ├── build_apk.sh            Build APK inside Docker  ← primary build script
    ├── build_alpine_base.sh    Build Alpine base image with Docker + Python baked in
    ├── alpine_build_inner.sh   Inner image build logic (runs inside Alpine container)
    └── firebase_test.sh        Run Robo test on Firebase Test Lab
```

---

## Getting started

### 1. Clone

```bash
git clone <repo-url>
cd docker-app
```

### 2. Build the Alpine base image

The base image bundles Alpine Linux with Docker, Python, and the API server pre-installed. This step takes ~10–15 minutes and only needs to be rerun when `guest/` files change.

```bash
./scripts/build_alpine_base.sh
# Output: android/app/src/main/assets/vm/base.qcow2.gz (~102 MB)
```

The QEMU binaries and kernel/initrd are already committed in `jniLibs/` and `assets/vm/` — no separate acquisition step is needed.

### 3. Build the APK

```bash
./scripts/build_apk.sh
# Output: build/docker-vm-debug.apk (~220 MB)
```

First build takes ~10 minutes (downloads JDK + Android SDK + Flutter inside Ubuntu Docker image). Subsequent builds reuse the cached builder image.

### 4. Install

```bash
adb install -r build/docker-vm-debug.apk
```

---

## First run

1. Open the app → tap **Start VM**
2. Assets extract to app-private storage on first launch (~10–30 seconds)
3. QEMU boots Alpine Linux (~30–60 seconds)
4. `init_bootstrap.sh` runs on the very first boot — installs Docker and starts the API server (~5–10 minutes)
5. Once the `/health` check passes, the dashboard shows **RUNNING** and containers can be managed

> **First boot only** is slow because Docker is installed from Alpine packages inside the VM. Subsequent boots take 30–60 seconds, and previously pulled Docker images are available instantly (persistent `user.qcow2` overlay).

---

## Guest API

All endpoints except `/health` require `Authorization: Bearer <token>`.

| Method | Path | Body / Query | Description |
|---|---|---|---|
| GET | `/health` | — | `{"status","runtime","version"}` |
| GET | `/containers` | — | List all containers |
| POST | `/containers/start` | `{"image","name","cmd","env","ports","network"}` | Pull image then run container |
| POST | `/containers/stop` | `{"name"}` | Stop a container |
| GET | `/logs` | `?name=&tail=` | Container logs |
| POST | `/images/pull` | `{"image"}` | Pull an image (300s timeout) |
| POST | `/exec` | `{"name","cmd"}` | Exec command in a container |
| POST | `/vm/exec` | `{"cmd"}` | Run shell command on VM host |

### Timeout contract

`/containers/start` runs `docker pull` (up to 300 s) then `docker run` (up to 30 s). The Android `VmApiClient` uses a 360 s read timeout to cover both steps.

---

## Architecture notes

### Why a VM?

Stock Android kernels disable `CONFIG_USER_NS` (required for Docker rootless mode) and restrict cgroup access for regular apps. A QEMU VM provides a complete Linux environment with its own kernel — Docker runs normally inside it.

### Networking

QEMU uses SLIRP user-mode networking (no root required):

- `hostfwd=tcp::7080-:7080` — Android port 7080 → guest `10.0.2.15:7080`
- Guest API server **must** listen on `0.0.0.0:7080` (not `127.0.0.1`) so SLIRP-forwarded connections reach it
- Android cleartext HTTP allowed for `127.0.0.1` via `res/xml/network_security_config.xml`
- ICMP/ping does not work inside the guest (SLIRP limitation)

### Token auth

A UUID token is generated on first app launch (`vm_app_prefs`) and injected into every QEMU boot via:

```
-append "... api_token=<TOKEN> ..."
```

The guest reads it from `/proc/cmdline`. Every API request must include `Authorization: Bearer <token>`.

### Docker daemon constraints

Alpine's kernel (`linux-virt`) ships without `nf_tables`, `bridge`, or `overlay` modules. The Docker daemon is configured accordingly:

```json
{
  "iptables": false,
  "bridge": "none",
  "dns": ["8.8.8.8", "8.8.4.4"]
}
```

Containers use `--network host` to share the VM's SLIRP network interface.

### DNS

`/etc/resolv.conf` in the VM lists three nameservers with `options use-vc` (force TCP) to work around SLIRP UDP unreliability:

```
nameserver 10.0.2.3
nameserver 8.8.8.8
nameserver 8.8.4.4
options timeout:2 attempts:2 use-vc
```

### Persistent Docker image cache

`user.qcow2` is a QCOW2 overlay backed by `base.qcow2`. It persists across VM restarts so pulled Docker images are available on the next boot without re-downloading. The overlay is only recreated when `base.qcow2` is freshly extracted (i.e., on first install or app update).

---

## Firebase Test Lab

Automated Robo tests run on `Pixel2.arm` (ARM64), Android 11 (API 30):

```bash
./scripts/firebase_test.sh docker-28f14 Pixel2.arm 30
```

Requires `service-account-key.json` in the project root (gitignored).

---

## Licensing

| Component | License |
|---|---|
| QEMU | GPLv2 (TCG: BSD/Expat) |
| Alpine Linux | MIT / various |
| Docker | Apache 2.0 |
| Flutter | BSD 3-Clause |

All four components can be used in commercial and proprietary projects. QEMU runs as a separate process (not linked), so GPLv2 copyleft does not apply to your own app code — you only need to include the license text and make the QEMU source available.

See [`LICENSES.md`](LICENSES.md) for the full breakdown and compliance checklist.

---

## Related

- [termux-docker-no-root](https://github.com/mabdulmoghni/termux-docker-no-root) — community validation of the VM-based approach this project is based on
