#!/bin/bash
# Extract QEMU binaries from Termux APK or running Termux installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets/qemu"
TOOLS_DIR="${PROJECT_ROOT}/tools"

echo "=== Extract QEMU Binaries from Termux ==="
echo ""

mkdir -p "${ASSETS_DIR}"
mkdir -p "${TOOLS_DIR}"

echo "This script will help you extract QEMU binaries from Termux."
echo ""
echo "You have two options:"
echo "  1. Extract from device with adb (requires Termux installed and QEMU packages)"
echo "  2. Extract from downloaded Termux APK file"
echo ""
read -p "Choose option (1 or 2): " -n 1 -r
echo ""

if [[ $REPLY == "1" ]]; then
    # Option 1: Extract from running Termux via adb
    echo ""
    echo "=== Option 1: Extract via ADB ==="
    echo ""

    # Check for adb
    if ! command -v adb &> /dev/null; then
        echo "ERROR: adb not found!"
        echo "Please install Android SDK Platform Tools."
        exit 1
    fi

    # Check device connection
    echo "Checking for connected devices..."
    DEVICES=$(adb devices | grep -w "device" | wc -l)
    if [ ${DEVICES} -eq 0 ]; then
        echo "ERROR: No Android devices connected."
        echo "Please connect your device and enable USB debugging."
        exit 1
    fi

    echo "Device connected!"
    echo ""
    echo "Make sure Termux is installed on your device and run:"
    echo "  pkg update"
    echo "  pkg install qemu-system-aarch64-headless qemu-utils"
    echo ""
    read -p "Have you installed QEMU in Termux? (y/n) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please install QEMU packages first, then run this script again."
        exit 1
    fi

    # Pull binaries
    echo "Pulling QEMU binaries from device..."

    TERMUX_PREFIX="/data/data/com.termux/files/usr"

    echo "Pulling qemu-system-aarch64..."
    adb pull "${TERMUX_PREFIX}/bin/qemu-system-aarch64" "${ASSETS_DIR}/qemu-system-aarch64" || {
        echo "ERROR: Failed to pull qemu-system-aarch64"
        echo "Make sure Termux QEMU is installed: pkg install qemu-system-aarch64-headless"
        exit 1
    }

    echo "Pulling qemu-img..."
    adb pull "${TERMUX_PREFIX}/bin/qemu-img" "${ASSETS_DIR}/qemu-img" || {
        echo "ERROR: Failed to pull qemu-img"
        echo "Make sure Termux QEMU is installed: pkg install qemu-utils"
        exit 1
    }

    echo ""
    echo "✅ Binaries extracted successfully!"

elif [[ $REPLY == "2" ]]; then
    # Option 2: Extract from APK
    echo ""
    echo "=== Option 2: Extract from APK ==="
    echo ""

    APK_DIR="${TOOLS_DIR}/termux_apk"
    mkdir -p "${APK_DIR}"

    echo "Download Termux APK from:"
    echo "  https://f-droid.org/en/packages/com.termux/"
    echo ""
    echo "Then download the QEMU packages (.deb files) from:"
    echo "  https://packages.termux.dev/apt/termux-main/pool/main/"
    echo "  - qemu-system-aarch64-headless"
    echo "  - qemu-utils"
    echo ""
    echo "Place the .deb files in: ${APK_DIR}"
    echo ""
    read -p "Have you downloaded the files? (y/n) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please download the files first, then run this script again."
        exit 0
    fi

    # Check for .deb files
    DEB_FILES=$(find "${APK_DIR}" -name "*.deb" 2>/dev/null | wc -l)
    if [ ${DEB_FILES} -eq 0 ]; then
        echo "ERROR: No .deb files found in ${APK_DIR}"
        exit 1
    fi

    echo "Found ${DEB_FILES} .deb files"
    echo ""

    # Extract .deb files
    for DEB_FILE in "${APK_DIR}"/*.deb; do
        echo "Extracting: $(basename ${DEB_FILE})"

        # Create temp directory
        TEMP_DIR=$(mktemp -d)

        # Extract .deb (it's an ar archive)
        cd "${TEMP_DIR}"
        ar -x "${DEB_FILE}" 2>/dev/null || {
            echo "  Trying dpkg-deb..."
            dpkg-deb -x "${DEB_FILE}" . 2>/dev/null || {
                echo "  ERROR: Failed to extract. Install dpkg-deb or ar utility."
                rm -rf "${TEMP_DIR}"
                continue
            }
        }

        # Find and extract data.tar.*
        if [ -f "data.tar.xz" ]; then
            tar -xf data.tar.xz
        elif [ -f "data.tar.gz" ]; then
            tar -xf data.tar.gz
        elif [ -f "data.tar.zst" ]; then
            tar -xf data.tar.zst
        fi

        # Copy binaries
        if [ -f "data/data/com.termux/files/usr/bin/qemu-system-aarch64" ]; then
            cp "data/data/com.termux/files/usr/bin/qemu-system-aarch64" "${ASSETS_DIR}/"
            echo "  ✓ Extracted qemu-system-aarch64"
        fi

        if [ -f "data/data/com.termux/files/usr/bin/qemu-img" ]; then
            cp "data/data/com.termux/files/usr/bin/qemu-img" "${ASSETS_DIR}/"
            echo "  ✓ Extracted qemu-img"
        fi

        # Cleanup
        cd "${PROJECT_ROOT}"
        rm -rf "${TEMP_DIR}"
    done

else
    echo "Invalid option."
    exit 1
fi

# Verify extracted binaries
echo ""
echo "=== Verifying Binaries ==="

for BINARY in qemu-system-aarch64 qemu-img; do
    BINARY_PATH="${ASSETS_DIR}/${BINARY}"

    if [ ! -f "${BINARY_PATH}" ]; then
        echo "❌ ${BINARY}: NOT FOUND"
        continue
    fi

    # Check file type
    FILE_TYPE=$(file "${BINARY_PATH}")
    echo ""
    echo "${BINARY}:"
    echo "  Path: ${BINARY_PATH}"
    echo "  Size: $(ls -lh ${BINARY_PATH} | awk '{print $5}')"
    echo "  Type: ${FILE_TYPE}"

    # Check if it's ELF aarch64
    if echo "${FILE_TYPE}" | grep -q "ELF 64-bit.*aarch64"; then
        echo "  ✅ Valid aarch64 binary"
    else
        echo "  ⚠️  Warning: May not be aarch64 binary"
    fi

    # Generate checksum
    echo "  SHA-256: $(shasum -a 256 ${BINARY_PATH} | awk '{print $1}')"
done

echo ""
echo "=== Summary ==="
echo "Binaries saved to: ${ASSETS_DIR}"
echo ""

# Check if both binaries exist
if [ -f "${ASSETS_DIR}/qemu-system-aarch64" ] && [ -f "${ASSETS_DIR}/qemu-img" ]; then
    echo "✅ All required binaries extracted!"
    echo ""
    echo "Total size: $(du -sh ${ASSETS_DIR} | awk '{print $1}')"
else
    echo "❌ Some binaries are missing. Please check the extraction process."
    exit 1
fi
