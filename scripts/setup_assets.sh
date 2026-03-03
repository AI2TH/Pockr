#!/bin/bash
# Master asset setup script for the Docker VM app.
# REQUIRES: Docker (all downloads, builds, and tools run inside containers).
# Nothing is downloaded or executed directly on the host.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Docker VM App — Asset Setup                         ║"
echo "║  All operations run inside Docker containers               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Docker is the only host dependency
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is the only required tool and it was not found."
    echo "       Install Docker Desktop: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "✓ Docker $(docker --version | cut -d' ' -f3 | tr -d ',')"
echo ""

echo "Select what to set up:"
echo ""
echo "  1. Bootstrap scripts only   — copy guest/ scripts into assets/"
echo "  2. Alpine Linux image       — download + convert (~50 MB, uses Docker)"
echo "  3. QEMU binaries            — extract from Termux .deb packages (uses Docker)"
echo "  4. Build QEMU from source   — cross-compile inside Docker (slow, ~20 min)"
echo "  5. Full setup               — steps 1 + 2 + 3"
echo "  6. Generate checksums       — for all existing assets"
echo "  7. Verify assets            — validate everything before APK build"
echo "  8. Test API server          — run guest API server tests in Docker"
echo ""
read -r -p "Choose option (1-8): " REPLY
echo ""

case $REPLY in
    1)
        bash "${SCRIPT_DIR}/copy_bootstrap.sh"
        ;;
    2)
        bash "${SCRIPT_DIR}/download_alpine.sh"
        ;;
    3)
        bash "${SCRIPT_DIR}/extract_from_termux.sh"
        ;;
    4)
        bash "${SCRIPT_DIR}/build_qemu.sh"
        ;;
    5)
        echo "--- Step 1/3: Bootstrap scripts ---"
        bash "${SCRIPT_DIR}/copy_bootstrap.sh"
        echo ""
        echo "--- Step 2/3: Alpine Linux image ---"
        bash "${SCRIPT_DIR}/download_alpine.sh"
        echo ""
        echo "--- Step 3/3: QEMU binaries ---"
        echo "Choose extraction method (Termux .deb or build from source):"
        echo "  t = extract from Termux .deb packages"
        echo "  b = build from source (slow)"
        read -r -p "Choice (t/b): " QEMU_CHOICE
        if [[ $QEMU_CHOICE == "b" ]]; then
            bash "${SCRIPT_DIR}/build_qemu.sh"
        else
            bash "${SCRIPT_DIR}/extract_from_termux.sh"
        fi
        echo ""
        echo "--- Generating checksums ---"
        bash "${SCRIPT_DIR}/generate_checksums.sh"
        ;;
    6)
        bash "${SCRIPT_DIR}/generate_checksums.sh"
        ;;
    7)
        bash "${SCRIPT_DIR}/verify_assets.sh"
        ;;
    8)
        bash "${SCRIPT_DIR}/test_api.sh"
        ;;
    *)
        echo "Invalid option: $REPLY"
        exit 1
        ;;
esac

echo ""
echo "Done."
