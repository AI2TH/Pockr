# Architecture — Quick Reference

Companion to [ARCHITECTURE.md](ARCHITECTURE.md). This file is a condensed reference for the most commonly needed technical details.

---

## Call chain

```
Flutter UI (Dart)
  └── VmPlatform.vmExec() / VmPlatform.startVm() / ...
        └── MethodChannel("com.example.dockerapp/vm")
              └── MainActivity.kt — switch on call.method
                    └── VmManager.kt
                          └── VmApiClient.kt — OkHttp → http://127.0.0.1:7080
                                └── api_server.py (FastAPI in Alpine VM)
                                      └── docker / sh -c
```

---

## Key file paths (on device)

| Path | Contents |
|---|---|
| `context.applicationInfo.nativeLibraryDir` | `libqemu.so`, `libqemu_img.so`, `lib*.so` |
| `context.filesDir/vm/base.qcow2` | Decompressed Alpine base image |
| `context.filesDir/vm/user.qcow2` | Persistent writable overlay (Docker image cache) |
| `context.filesDir/vm/vmlinuz-virt` | Alpine kernel |
| `context.filesDir/vm/initramfs-virt` | Alpine initrd |
| `context.filesDir/bootstrap/` | `api_server.py`, `init_bootstrap.sh` |
| `context.filesDir/assets_extracted.v11` | Extraction version marker |

---

## OkHttp clients in VmApiClient

| Client | Connect | Read | Write | Used for |
|---|---|---|---|---|
| `client` (default) | 5 s | 10 s | 30 s | health, containers list, logs, stop |
| `containerClient` | 5 s | 360 s | 30 s | `/containers/start` (pull 300s + run 30s) |

---

## Guest API endpoints

| Method | Path | Auth | Timeout (server) |
|---|---|---|---|
| GET | `/health` | No | 5 s |
| GET | `/containers` | Yes | — |
| POST | `/containers/start` | Yes | pull 300s + run 30s |
| POST | `/containers/stop` | Yes | 15 s |
| GET | `/logs` | Yes | — |
| POST | `/images/pull` | Yes | 300 s |
| POST | `/exec` | Yes | 30 s |
| POST | `/vm/exec` | Yes | 30 s |

---

## Alpine Docker daemon config (`/etc/docker/daemon.json`)

```json
{
  "iptables": false,
  "bridge": "none",
  "dns": ["8.8.8.8", "8.8.4.4"],
  "ip-masq": false,
  "userland-proxy": false
}
```

Required because `linux-virt` kernel has no `nf_tables`, `bridge`, or `overlay` modules.
Storage driver: `vfs` (auto-detected).

---

## Alpine `/etc/resolv.conf`

```
nameserver 10.0.2.3
nameserver 8.8.8.8
nameserver 8.8.4.4
options timeout:2 attempts:2 use-vc
```

`use-vc` forces TCP DNS — SLIRP UDP proxy is unreliable on some networks.

---

## Token injection path

```
VmManager: UUID stored in vm_app_prefs → api_token
  └── QEMU: -append "... api_token=<UUID> ..."
        └── Alpine: /proc/cmdline
              └── api_server.py: _load_token() → parses /proc/cmdline
```

Fallback chain in `api_server.py`:
1. `/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw` (requires `qemu_fw_cfg` module — may not be loaded)
2. `/bootstrap/token` (written by asset extraction)
3. `API_TOKEN` environment variable
4. Kernel cmdline `api_token=` (primary reliable path)

---

## SharedPreferences keys

| Setting | File | Key | Type note |
|---|---|---|---|
| vCPU count | `FlutterSharedPreferences` | `flutter.vcpu_count` | Stored as Long on Android |
| RAM (MB) | `FlutterSharedPreferences` | `flutter.ram_mb` | Stored as Long on Android |
| API token | `vm_app_prefs` | `api_token` | String |

VmManager uses `getFlutterInt()` to safely cast Long → Int.

---

## Asset extraction marker versioning

Marker file: `assets_extracted.vN` in `context.filesDir`

Bump `N` in `VmManager.assetsReady()` and `VmManager.extractAssets()` whenever `base.qcow2.gz` content changes (i.e. after rebuilding the Alpine base image).

Current: **v11**

---

## user.qcow2 lifecycle

```
assetsReady() → false (marker missing or base changed)
  └── extractAssets() → freshExtraction = true
        └── startVm() → delete + recreate user.qcow2

assetsReady() → true AND user.qcow2 exists
  └── startVm() → reuse existing user.qcow2 (Docker cache intact)
```

---

## Firebase Test Lab

- Device: `Pixel2.arm` — ARM64, Android 11 (API 30)
- Project: `<your-gcp-project>`
- GCS bucket: `<your-gcs-bucket>`
- Latest passing build: **v31** (GitHub Releases download URL, Google Drive removed)

```bash
./scripts/firebase_test.sh <your-gcp-project> Pixel2.arm 30
```

### v28 logcat findings (2026-03-03)

| Event | Time | Notes |
|---|---|---|
| Assets extracted, QEMU launched | 01:11:06 | Fresh extraction, ~1 s |
| VM running / API warming up | 01:11:06 | Alpine boots in ~60–90 s |
| `alpine_*` + `busybox` containers started | 01:14:40–01:14:48 | Pull + run via API — confirmed working |
| `free -h` crash | 01:14:21 | `exitCode` returned as `Double` not `Int` — **fixed in v29** |
| Dashboard header "Docker on Android" | visible | Old hardcoded title — **fixed in v29** |

VM was stopped 3× by the Robo test tapping "Stop Engine". This is expected Robo behaviour, not a crash.

---

## ELF / jniLibs notes

50 ARM64 Termux-derived shared libs in `jniLibs/arm64-v8a/`.

- **Do not use patchelf** — it restructures LOAD segments causing Android 11 linker to abort (`Load CHECK did_read_ failed`)
- RUNPATH was cleared in-place with `scripts/fix_elf_inplace.py` (zeroes `d_val` only, preserves `d_tag`)
- Baseline restored from git commit `f7bc7d1` (pre-patchelf)

_Last updated: 2026-03-03 (v29)_
