# Architecture — Docker on Android (No Root)

## 1. Objective

A single Android APK that runs Docker/OCI containers on non-rooted devices by embedding a QEMU virtual machine running Alpine Linux. No external apps (no Termux), no root required.

---

## 2. Why a VM is Required

Stock Android kernels on non-rooted devices lack the features Docker needs:

- `CONFIG_USER_NS` is absent from the Android GKI ARM64 `gki_defconfig` — Docker rootless mode requires user namespaces. [Source: [gki_defconfig](https://android.googlesource.com/kernel/common/+/refs/heads/android-mainline/arch/arm64/configs/gki_defconfig)]
- cgroups, overlayfs, and network namespaces are restricted for regular app processes
- No mechanism to run a container daemon with the required capabilities

A QEMU VM provides a complete Linux environment with its own kernel. Docker runs normally inside the guest without any device root.

Validated approach: [termux-docker-no-root](https://github.com/mabdulmoghni/termux-docker-no-root) — community demonstration of Docker on Android via QEMU + Alpine (no root).

---

## 3. High-Level Architecture

```
Android OS (non-rooted)
└── APK (Flutter + Kotlin)
    ├── DockerApp (Application singleton)
    │   └── VmManager — asset extraction, QEMU lifecycle
    │       └── VmApiClient — HTTP client (auth token)
    ├── VmService — ForegroundService (persistent notification)
    └── Flutter UI — 4 tabs: Dashboard, Containers, Terminal, Settings
          └── VmPlatform (MethodChannel) ──▶ Kotlin

QEMU process (qemu-system-aarch64)
└── Alpine Linux 3.19 (aarch64) VM
    ├── Docker daemon (iptables=false, bridge=none, --network host)
    └── FastAPI server (api_server.py) on 0.0.0.0:7080
          ↑
          SLIRP hostfwd tcp::7080-:7080
          ↑
http://127.0.0.1:7080 (from Android app)
```

---

## 4. Components

### 4.1 Android App (Kotlin + Flutter)

**DockerApp** (`Application` subclass) holds the `VmManager` singleton, ensuring the QEMU process survives Activity recreation.

**VmManager** handles:
- First-run asset extraction from `AssetManager` to app-private storage
- `user.qcow2` overlay creation via `libqemu_img.so`
- QEMU launch via `ProcessBuilder`
- Health checking and lifecycle (start/stop/restart)

**VmApiClient** is an OkHttp client that:
- Signs every request with `Authorization: Bearer <token>`
- Uses a 360 s read timeout on the container endpoint (300 s pull + 30 s run + buffer)
- Uses a 10 s read timeout on the health endpoint

**VmService** is a `ForegroundService` that keeps the VM alive when the app is backgrounded and shows a persistent notification.

**Flutter UI** uses a `MethodChannel` to call Kotlin from Dart and a `VmState` provider that polls `/health` every 5 seconds.

### 4.2 QEMU Setup

QEMU binaries are installed by Android's `PackageManager` from `jniLibs/arm64-v8a/` into `nativeLibraryDir` with `exec_type` SELinux label — safe to execute on Android 10+.

| File | Role |
|---|---|
| `libqemu.so` | `qemu-system-aarch64` |
| `libqemu_img.so` | `qemu-img` (creates `user.qcow2`) |
| `lib*.so` (×48) | Shared dependencies (glib, zlib, gnutls, etc.) |

`LD_LIBRARY_PATH` is set to `nativeLibraryDir` when launching both QEMU processes.

### 4.3 VM Disk Layout

| Image | Type | Description |
|---|---|---|
| `base.qcow2.gz` | Asset (compressed) | Read-only Alpine root with Docker + Python |
| `base.qcow2` | Extracted | Decompressed on first run |
| `user.qcow2` | QCOW2 overlay | Writable overlay backed by `base.qcow2` (8 GB virtual) |

`user.qcow2` is **persistent**: it is only recreated when `base.qcow2` was freshly extracted (app update changed the base image) or when it does not exist yet. All pulled Docker image layers survive VM restarts.

### 4.4 Guest (Alpine VM)

**init_bootstrap.sh** runs on the very first boot to install Docker CE and start the API server. OpenRC brings up Docker and the API server on every subsequent boot.

**api_server.py** is a FastAPI application that exposes the REST API. It listens on `0.0.0.0:7080` — SLIRP delivers hostfwd connections to the guest's `eth0` address (`10.0.2.15`), not loopback.

Docker daemon config (`/etc/docker/daemon.json`):
```json
{
  "iptables": false,
  "bridge": "none",
  "dns": ["8.8.8.8", "8.8.4.4"],
  "ip-masq": false,
  "userland-proxy": false
}
```
`linux-virt` kernel does not include `nf_tables`, `bridge`, or `overlay` modules. This config avoids all of them. Storage driver auto-selects `vfs`.

---

## 5. Networking

### SLIRP (user-mode networking)

```
Android :7080  ──hostfwd──▶  guest 10.0.2.15:7080
```

Key constraints:
- No root required
- ICMP/ping does not work inside the guest
- Guest is not directly accessible from outside — only via explicit `hostfwd` ports
- Performance is lower than tap/bridge networking

### DNS in the VM

`/etc/resolv.conf`:
```
nameserver 10.0.2.3
nameserver 8.8.8.8
nameserver 8.8.4.4
options timeout:2 attempts:2 use-vc
```

`use-vc` forces all DNS queries to TCP. SLIRP's UDP DNS proxy (`10.0.2.3`) is unreliable on some devices/networks; `8.8.8.8` and `8.8.4.4` as fallbacks ensure Docker Hub pulls succeed.

### Android network security

Android 9+ blocks cleartext HTTP by default. `res/xml/network_security_config.xml` explicitly allows cleartext for `127.0.0.1`. Referenced from `AndroidManifest.xml`.

---

## 6. Token Authentication

1. `VmManager` generates a UUID on first launch and stores it in `vm_app_prefs`
2. Every QEMU boot injects the token via `-append`:
   ```
   console=ttyAMA0 root=/dev/vda ... api_token=<UUID> quiet
   ```
3. `api_server.py` reads it at startup from `/proc/cmdline`
4. Every API call (except `/health`) requires `Authorization: Bearer <UUID>`

---

## 7. Guest API Reference

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | No | Docker daemon status + version |
| GET | `/containers` | Yes | List all containers |
| POST | `/containers/start` | Yes | Pull image (300 s) then run (30 s) |
| POST | `/containers/stop` | Yes | Stop a named container |
| GET | `/logs` | Yes | Container logs (`?name=&tail=`) |
| POST | `/images/pull` | Yes | Explicit image pull (300 s) |
| POST | `/exec` | Yes | Exec command inside a container |
| POST | `/vm/exec` | Yes | Run shell command on the Alpine VM host |

### `/containers/start` timeout chain

```
api_server.py:  docker pull (timeout=300s) + docker run (timeout=30s)
VmApiClient:    containerClient readTimeout = 360s
```

### `/vm/exec`

Runs `sh -c <cmd>` on the Alpine host (not inside a container). Returns `{stdout, stderr, exitCode}`. Used by the Terminal screen. Timeout: 30 s.

---

## 8. Settings and SharedPreferences

The Settings screen writes vCPU count and RAM to Flutter `SharedPreferences`. On Android, `SharedPreferences` stores integers as `Long`. `VmManager` handles this:

```kotlin
private fun getFlutterInt(key: String, default: Int): Int {
    return try {
        flutterPrefs.getInt(key, default)
    } catch (_: ClassCastException) {
        flutterPrefs.getLong(key, default.toLong()).toInt()
    }
}
```

| Preference | File | Key |
|---|---|---|
| vCPU count | `FlutterSharedPreferences` | `flutter.vcpu_count` |
| RAM (MB) | `FlutterSharedPreferences` | `flutter.ram_mb` |
| API token | `vm_app_prefs` | `api_token` |

### MethodChannel numeric types

Numeric values returned from Kotlin via `MethodChannel` are decoded as `Double` in Dart, not `Int`. Always cast with `(result['exitCode'] as num?)?.toInt()`, never `as int?` directly.

---

## 9. QEMU Launch Command

```
libqemu.so
  -machine virt
  -cpu cortex-a53
  -smp <vcpu>
  -m <ram>
  -drive if=none,file=base.qcow2,id=base,format=qcow2,readonly=on
  -drive if=none,file=user.qcow2,id=user,format=qcow2
  -device virtio-blk-pci,drive=user
  -netdev user,id=net0,hostfwd=tcp::7080-:7080
  -device virtio-net-pci,netdev=net0,romfile=
  -fw_cfg name=opt/api_token,string=<TOKEN>
  -display none
  -serial stdio
  -kernel vmlinuz-virt
  -initrd initramfs-virt
  -append "console=ttyAMA0 root=/dev/vda rootfstype=ext4 rootflags=rw modules=virtio_blk,ext4 api_token=<TOKEN> quiet"
```

Notes:
- `-serial stdio` routes ttyAMA0 output to Java stdout → Android logcat
- `romfile=` on `virtio-net-pci` avoids the ROM lookup that fails without PCI ROM support
- Token appears in both `-fw_cfg` and `-append`; guest uses `/proc/cmdline` (kernel cmdline) as primary because it doesn't require the `qemu_fw_cfg` kernel module

---

## 10. Build System

| Stage | Docker image | Output |
|---|---|---|
| Alpine base | `arm64v8/alpine:3.19` | `base.qcow2.gz` |
| APK build | `ubuntu:22.04` (amd64) | `pockr-release.apk` (~164 MB) |

The APK builder must use `--platform linux/amd64` on Apple Silicon Macs. The builder image is tagged `docker-app-builder`.

---

## 11. Asset Extraction Versioning

`VmManager.assetsReady()` checks for a marker file (`assets_extracted.vN`). Bump `N` whenever `base.qcow2.gz` changes (i.e., after rebuilding the Alpine base image) to force re-extraction on the next app launch.

Current version: **v11**

---

## 12. Security Notes

- VM API is only accessible via `127.0.0.1:7080` (SLIRP hostfwd) — not reachable from outside the device
- App-private storage (`/data/data/<app>/files/`) is inaccessible to other apps
- Docker remote TCP socket is **not** enabled — all Docker management goes through the internal API server
- Guest API validates the auth token on every authenticated endpoint

---

## 13. Limitations

- ARM64 only — `jniLibs` contains only `arm64-v8a` QEMU binaries
- No KVM — software TCG emulation only (KVM requires kernel module access unavailable on stock Android)
- SLIRP networking — lower throughput than tap/bridge; no ICMP
- Docker containers must use `--network host` — bridge networking requires kernel modules not present in `linux-virt`
- Battery and RAM overhead — a 2 GB RAM allocation is recommended; the VM runs continuously in the background

---

## 14. References

| Topic | Source |
|---|---|
| QEMU hostfwd / SLIRP networking | https://wiki.qemu.org/Documentation/Networking |
| QEMU license (GPLv2 + TCG BSD) | https://wiki.qemu.org/License |
| Docker rootless mode prerequisites | https://docs.docker.com/engine/security/rootless/ |
| Android GKI ARM64 defconfig (CONFIG_USER_NS absent) | https://android.googlesource.com/kernel/common/+/refs/heads/android-mainline/arch/arm64/configs/gki_defconfig |
| Android ForegroundService | https://developer.android.com/develop/background-work/services/fgs |
| Community validation: Docker on Android via VM | https://github.com/mabdulmoghni/termux-docker-no-root |

_Last updated: 2026-03-03 (v29)_
