---
name: firebase-test
description: Run Firebase Test Lab Robo test for Pockr APK, download logcat results, and analyse findings. Use when user asks to run firebase test, check test results, download logcat, or analyse a test run.
tools: Bash, Read, Grep
---

# Firebase Test Skill — Pockr

## Directory Layout

```
~/Desktop/MAIN/kalvin/testcase_and_creds/
  service-account-key.json       # GCP service account (never commit)
  test-results/
    logcat_v<N>.txt              # downloaded logcats, one per APK version
    2026-<date>_firebase*/       # raw GCS result folders (downloaded manually)
    v<N>/                        # older named result folders
    *.png                        # screenshots from Robo crawler
```

APK to test: `build/pockr-release.apk` (built by `./scripts/build_apk.sh release`)

## Step 1 — Build (if needed)

```bash
./scripts/build_apk.sh release
# Output: build/pockr-release.apk (~177 MB)
```

## Step 2 — Run Firebase Test

```bash
./scripts/firebase_test.sh <your-gcp-project> Pixel2.arm 30
```

- Credentials: `~/Desktop/MAIN/kalvin/testcase_and_creds/service-account-key.json`
- Device: `Pixel2.arm` — ARM64, Android 11 (API 30)
- Timeout: 600s
- Type: Robo (automated UI crawler)

The command prints a GCS bucket path and a Firebase Console URL when the test starts. Save the GCS run path — you need it for logcat download.

## Step 3 — Download Logcat

After the test finishes, download the logcat using the GCS path printed during the run:

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$HOME/Desktop/MAIN/kalvin/testcase_and_creds/service-account-key.json:/creds.json:ro" \
  -v "$HOME/Desktop/MAIN/kalvin/testcase_and_creds/test-results:/out" \
  gcr.io/google.com/cloudsdktool/google-cloud-cli:stable \
  bash -c '
gcloud auth activate-service-account --key-file=/creds.json --quiet 2>/dev/null
gsutil cp "gs://<your-gcs-bucket>/<run-id>/Pixel2.arm-30-en-portrait/logcat" /out/logcat_v<N>.txt
echo "Done"
'
```

Replace `<your-gcs-bucket>`, `<run-id>`, and `<N>` with the actual values from the test output.

Save logcats as `logcat_v<N>.txt` where N is the APK version number.

## Step 4 — Analyse Results

Filter logcat for Pockr app lines only:

```bash
grep -E "D VmManager|I VmManager|W VmManager|E VmManager|D VmService|I VmService|W VmService|E VmService|D VmApiClient|I VmApiClient|W VmApiClient|E VmApiClient" \
  ~/Desktop/MAIN/kalvin/testcase_and_creds/test-results/logcat_v<N>.txt
```

### Key events to look for

| Log line | Meaning |
|---|---|
| `VmManager: Starting VM...` | VM launch triggered by user/Robo |
| `VmManager: Assets not ready, extracting...` | Fresh install — first boot |
| `VmManager: Extracted vm/base.qcow2` | Asset extraction OK |
| `VmManager: QEMU command: ...` | QEMU launched (check args) |
| `VmManager: VM process launched` | QEMU running |
| `VmApiClient: Health check failed: timeout` | VM killed before API was ready (first boot slow) |
| `VmApiClient: Health check failed: Connection reset` | Alpine still booting — expected during startup |
| `VmApiClient: Container started: <name>` | Container successfully started — core flow working |
| `VmManager: VM stopped` | VM shut down cleanly |
| `VmManager: QEMU output reader closed` | Normal on stop |

### Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `Health check failed: timeout` on first boot | Alpine first-boot bootstrap takes ~2.5 min, health check kills at 35s | VM restarts and works on second attempt; increase health check timeout |
| `Health check failed: Connection reset` | Alpine still booting — not an error | Wait; API comes up within ~2.5 min |
| `Failed to connect to /127.0.0.1:7080` | VM not running | Normal after VM is stopped |
| No `Container started` line | Container pull/run never triggered | Check if Robo crawler reached Containers screen |
| `type 'double' is not a subtype of type 'int?'` | MethodChannel numeric cast | Cast via `(result['x'] as num?)?.toInt()` |

## Pass/Fail Criteria

- Firebase outcome: **Passed** = no crash, Robo completed crawl
- Functional: look for `VmApiClient: Container started:` — confirms VM + Docker + API all working end-to-end

## Logcat Naming Convention

Always name saved logcats `logcat_v<N>.txt` matching the APK version number so they correlate with MEMORY.md pass/fail history.

## Credential Security

- `service-account-key.json` lives only at `~/Desktop/MAIN/kalvin/testcase_and_creds/` — never inside the repo
- `.gitignore` covers `service-account*.json` and `service_account*.json`
- Never `git add` anything from `testcase_and_creds/`
