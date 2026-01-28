# Quick Setup Guide

Get the Docker VM app running in 4 steps.

## Prerequisites

- macOS or Linux development machine
- Android device (Android 8.0+, aarch64)
- USB cable and USB debugging enabled

## Step 1: Install Dependencies

```bash
# macOS
brew install qemu android-platform-tools

# Ubuntu/Debian
sudo apt-get install qemu-utils android-platform-tools

# Fedora
sudo dnf install qemu-img android-tools
```

## Step 2: Acquire Assets

```bash
cd /Users/kalvin.nathan/Desktop/MAIN/kalvin/docker-app

# Run automated setup
./scripts/setup_assets.sh
```

Choose:
- **Option 4**: Full automated setup (downloads Alpine)
- Then follow prompts for QEMU extraction

**OR manually run:**

```bash
# Download Alpine Linux
./scripts/download_alpine.sh

# Extract QEMU from Termux
./scripts/extract_from_termux.sh

# Generate checksums
./scripts/generate_checksums.sh
```

## Step 3: Verify Assets

```bash
./scripts/verify_assets.sh
```

Should show:
```
✅ All assets verified successfully!
```

## Step 4: Build and Install

```bash
# Build APK
cd android
./gradlew assembleDebug

# Install to device
adb install app/build/outputs/apk/debug/app-debug.apk

# Or build and install in one step
./gradlew installDebug
```

## Step 5: Test

1. Launch "Docker VM" app on device
2. Tap "Start VM" on dashboard
3. Wait 30-60 seconds for health check to pass
4. Tap "Run Test Container"
5. Go to "Containers" tab to see it running

---

## Troubleshooting

**App crashes on launch:**
```bash
adb logcat | grep dockerapp
```

**VM won't start:**
- Check logcat for errors
- Verify assets are present: `ls -lh android/app/src/main/assets/*/`
- Re-run `./scripts/verify_assets.sh`

**Health check fails:**
- VM may take up to 60 seconds to boot
- Check device has enough RAM (2GB needed)
- Try different vCPU/RAM settings in Settings screen

---

## Expected Behavior

**First launch (~2-3 minutes):**
1. Assets extraction: 5-10 seconds
2. VM boot: 30-60 seconds
3. Docker initialization: 20-40 seconds
4. API server start: 5-10 seconds

**Subsequent launches (~30-60 seconds):**
1. VM boot: 30-60 seconds (user.qcow2 already exists)

---

## File Sizes

**Assets:** ~65-75MB
**APK:** ~70-80MB
**Runtime storage:** ~150-200MB (with user.qcow2)

---

## Minimum Device Requirements

- Android 8.0 (API 26) or higher
- aarch64 (64-bit ARM) processor
- 2GB RAM minimum, 4GB recommended
- 500MB free storage
- Battery capacity to run VM (consumes 5-15% per hour)

---

## Next Steps

After basic setup works:
- Explore container management in the app
- Adjust vCPU/RAM in Settings
- Pull custom Docker images
- View container logs
- Try multi-container scenarios

See `BUILD_STATUS.md` for implementation details.
