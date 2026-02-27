#!/bin/bash
# Build the Flutter Android APK entirely inside Docker.
#
# Usage:
#   ./scripts/build_apk.sh            # debug build (default)
#   ./scripts/build_apk.sh release    # release build
#
# Output:
#   build/app-debug.apk   or
#   build/app-release.apk
#
# Requirements: Docker only.  No Flutter, Java, or Android SDK on the host.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_TYPE="${1:-debug}"
IMAGE_NAME="docker-app-builder"
OUTPUT_DIR="${PROJECT_ROOT}/build"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required."
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

# ── Build the builder image if it doesn't exist (always amd64 for consistency) ─
if ! docker image inspect "${IMAGE_NAME}" &>/dev/null; then
    echo "=== Building Docker build environment (first run — ~10 min) ==="
    docker build \
        --platform linux/amd64 \
        -f "${PROJECT_ROOT}/docker/Dockerfile.build" \
        -t "${IMAGE_NAME}" \
        "${PROJECT_ROOT}"
    echo ""
fi

echo "=== Building Flutter APK (${BUILD_TYPE}) inside Docker ==="
echo "Project : ${PROJECT_ROOT}"
echo "Output  : ${OUTPUT_DIR}/app-${BUILD_TYPE}.apk"
echo ""

# ── Run the build inside Docker ───────────────────────────────────────────────
# Strategy:
#   1. flutter create scaffolds a complete Android project (gradlew, gradle
#      wrapper, res/, etc.) in /tmp/workspace
#   2. We copy our source files (lib/, pubspec.yaml, Android sources) on top
#   3. flutter pub get + flutter build apk
#   4. APK is copied to the mounted /out volume

docker run --rm \
    --platform linux/amd64 \
    -v "${PROJECT_ROOT}:/src:ro" \
    -v "${OUTPUT_DIR}:/out" \
    "${IMAGE_NAME}" \
    bash -c "
set -e
git config --global --add safe.directory /opt/flutter 2>/dev/null || true

echo '--- Step 1: Scaffold fresh Flutter project ---'
flutter create \
    --no-pub \
    --project-name docker_app \
    --org com.example.dockerapp \
    --platforms android \
    /tmp/workspace

echo ''
echo '--- Step 2: Apply our sources over the scaffold ---'
cd /tmp/workspace

# Flutter Dart sources
cp -r /src/lib/. lib/
cp /src/pubspec.yaml pubspec.yaml
cp /src/analysis_options.yaml . 2>/dev/null || true

# Android app module
cp /src/android/app/build.gradle            android/app/build.gradle
cp /src/android/app/src/main/AndroidManifest.xml \
                                            android/app/src/main/AndroidManifest.xml
cp /src/android/build.gradle               android/build.gradle
cp /src/android/settings.gradle            android/settings.gradle
cp /src/android/gradle.properties          android/gradle.properties

# Kotlin sources (replace scaffold's MainActivity with ours)
rm -rf android/app/src/main/kotlin/
cp -r /src/android/app/src/main/kotlin     android/app/src/main/

# Assets (bootstrap scripts; qemu/ and vm/ dirs contain placeholders only)
mkdir -p android/app/src/main/assets
cp -r /src/android/app/src/main/assets/.  android/app/src/main/assets/

# Native libs (QEMU + all shared libs — arm64-v8a)
mkdir -p android/app/src/main/jniLibs
cp -r /src/android/app/src/main/jniLibs/. android/app/src/main/jniLibs/

# Signing keystore — ensures consistent APK signature across rebuilds
[ -f /src/android/app/debug.keystore ] && cp /src/android/app/debug.keystore android/app/debug.keystore || true

echo ''
echo '--- Step 2b: Fix Gradle wrapper to 8.3 (required by AGP 8.1.0) ---'
sed -i 's|distributionUrl=.*|distributionUrl=https\://services.gradle.org/distributions/gradle-8.3-all.zip|' \
    android/gradle/wrapper/gradle-wrapper.properties
echo \"Gradle: \$(grep distributionUrl android/gradle/wrapper/gradle-wrapper.properties)\"

# Write local.properties so settings.gradle can locate flutter.sdk
printf 'flutter.sdk=/opt/flutter\nsdk.dir=/opt/android-sdk\n' > android/local.properties

echo ''
echo '--- Step 3: flutter pub get ---'
flutter pub get

echo ''
echo '--- Step 4: flutter build apk (${BUILD_TYPE}) ---'
flutter build apk --${BUILD_TYPE} --verbose 2>&1 | tail -50

echo ''
echo '--- Step 5: Copy APK to output ---'
APK_SRC=\"build/app/outputs/flutter-apk/app-${BUILD_TYPE}.apk\"
APK_OUT=\"docker-vm-${BUILD_TYPE}.apk\"
if [ -f \"\$APK_SRC\" ]; then
    cp \"\$APK_SRC\" /out/\$APK_OUT
    echo \"APK size: \$(du -sh /out/\$APK_OUT | cut -f1)\"
else
    echo 'ERROR: APK not found at \$APK_SRC'
    ls -la build/app/outputs/flutter-apk/ 2>/dev/null || true
    exit 1
fi
"

echo ""
echo "✅  Build complete: ${OUTPUT_DIR}/docker-vm-${BUILD_TYPE}.apk"
echo ""
echo "Install on connected device:"
echo "  adb install ${OUTPUT_DIR}/docker-vm-${BUILD_TYPE}.apk"
