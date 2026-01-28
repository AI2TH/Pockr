#!/bin/bash
# Master script to set up all assets for the Docker VM app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Docker VM App - Asset Setup                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check for required tools
echo "Checking for required tools..."
MISSING_TOOLS=()

if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
    MISSING_TOOLS+=("wget or curl")
fi

if ! command -v gzip &> /dev/null; then
    MISSING_TOOLS+=("gzip")
fi

if ! command -v file &> /dev/null; then
    MISSING_TOOLS+=("file")
fi

if ! command -v shasum &> /dev/null; then
    MISSING_TOOLS+=("shasum")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "⚠️  Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Please install them:"
    echo "  macOS: brew install wget gzip coreutils"
    echo "  Ubuntu/Debian: sudo apt-get install wget gzip file coreutils"
    exit 1
fi

echo "✓ All basic tools available"
echo ""

# Menu
echo "Select asset acquisition method:"
echo ""
echo "  1. Quick setup - Copy bootstrap scripts only (no QEMU/Alpine)"
echo "  2. Download Alpine Linux image (~50MB download)"
echo "  3. Extract QEMU from Termux (requires device or APK)"
echo "  4. Full automated setup (Alpine + bootstrap)"
echo "  5. Generate checksums for existing assets"
echo "  6. Verify all assets"
echo ""
read -p "Choose option (1-6): " -n 1 -r
echo ""
echo ""

case $REPLY in
    1)
        echo "Running: copy_bootstrap.sh"
        bash "${SCRIPT_DIR}/copy_bootstrap.sh"
        ;;
    2)
        echo "Running: download_alpine.sh"
        bash "${SCRIPT_DIR}/download_alpine.sh"
        ;;
    3)
        echo "Running: extract_from_termux.sh"
        bash "${SCRIPT_DIR}/extract_from_termux.sh"
        ;;
    4)
        echo "Running full setup..."
        bash "${SCRIPT_DIR}/copy_bootstrap.sh"
        echo ""
        bash "${SCRIPT_DIR}/download_alpine.sh"
        echo ""
        echo "Next: Extract QEMU binaries manually (see ASSET_GUIDE.md)"
        echo "Then run option 5 to generate checksums."
        ;;
    5)
        echo "Running: generate_checksums.sh"
        bash "${SCRIPT_DIR}/generate_checksums.sh"
        ;;
    6)
        echo "Verifying assets..."
        bash "${SCRIPT_DIR}/verify_assets.sh"
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "Done!"
