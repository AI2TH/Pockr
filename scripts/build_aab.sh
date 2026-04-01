#!/bin/bash
# Build the Flutter Android AAB entirely inside Docker.
#
# Usage:
#   ./scripts/build_aab.sh            # release build (default)
#   ./scripts/build_aab.sh debug      # debug build
#
# Output:
#   build/pockr-release.aab   or
#   build/pockr-debug.aab
#
# Requirements: Docker only. No Flutter, Java, or Android SDK on the host.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_TYPE="${1:-release}"
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

echo "=== Building Flutter AAB (${BUILD_TYPE}) inside Docker ==="
echo "Project : ${PROJECT_ROOT}"
echo "Output  : ${OUTPUT_DIR}/pockr-${BUILD_TYPE}.aab"
echo ""

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
    --project-name pockr \
    --org com.ai2th \
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

# Android resources (network_security_config.xml, etc.) — merge into scaffold res/
cp -r /src/android/app/src/main/res/.  android/app/src/main/res/

# Assets (bootstrap scripts; qemu/ and vm/ dirs contain placeholders only)
mkdir -p android/app/src/main/assets
cp -r /src/android/app/src/main/assets/.  android/app/src/main/assets/

# Flutter assets (logo, images)
[ -d /src/assets ] && cp -r /src/assets/. assets/ || true

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

# Copy release signing config if present
if [ -f /src/android/key.properties ]; then
    cp /src/android/key.properties android/key.properties
    KEYSTORE_FILE=\$(grep '^storeFile=' android/key.properties | cut -d= -f2)
    [ -n \"\$KEYSTORE_FILE\" ] && [ -f \"/src/android/app/\$KEYSTORE_FILE\" ] && \
        cp \"/src/android/app/\$KEYSTORE_FILE\" \"android/app/\$KEYSTORE_FILE\" || true
fi

echo ''
echo '--- Step 3: flutter pub get ---'
flutter pub get

echo ''
echo '--- Step 3b: Generate launcher icons from logo ---'
dart run flutter_launcher_icons

echo ''
echo '--- Step 4: flutter build appbundle (${BUILD_TYPE}) ---'
flutter build appbundle --${BUILD_TYPE} --verbose 2>&1 | tail -50

echo ''
echo '--- Step 5: Copy AAB to output ---'
AAB_SRC=\"build/app/outputs/bundle/${BUILD_TYPE}/app-${BUILD_TYPE}.aab\"
AAB_OUT=\"pockr-${BUILD_TYPE}.aab\"
if [ -f \"\$AAB_SRC\" ]; then
    cp \"\$AAB_SRC\" /out/\$AAB_OUT
    echo \"AAB size: \$(du -sh /out/\$AAB_OUT | cut -f1)\"
else
    echo 'ERROR: AAB not found at \$AAB_SRC'
    ls -la build/app/outputs/bundle/ 2>/dev/null || true
    exit 1
fi
"

echo ""
echo "Build complete: ${OUTPUT_DIR}/pockr-${BUILD_TYPE}.aab"
