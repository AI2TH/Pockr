#!/bin/bash
# Copy bootstrap scripts to Android assets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUEST_DIR="${PROJECT_ROOT}/guest"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets/bootstrap"

echo "=== Copying Bootstrap Scripts to Assets ==="
echo ""

# Create assets directory
mkdir -p "${ASSETS_DIR}"

# Copy files
echo "Copying files from ${GUEST_DIR} to ${ASSETS_DIR}..."

FILES=(
    "api_server.py"
    "init_bootstrap.sh"
    "requirements.txt"
)

for FILE in "${FILES[@]}"; do
    if [ -f "${GUEST_DIR}/${FILE}" ]; then
        cp "${GUEST_DIR}/${FILE}" "${ASSETS_DIR}/"
        echo "  ✓ Copied ${FILE}"

        # Make scripts executable
        if [[ "${FILE}" == *.sh ]] || [[ "${FILE}" == *.py ]]; then
            chmod +x "${ASSETS_DIR}/${FILE}"
            echo "    (made executable)"
        fi
    else
        echo "  ⚠️  ${FILE} not found in ${GUEST_DIR}"
    fi
done

echo ""
echo "=== Bootstrap Assets ==="
ls -lh "${ASSETS_DIR}"

echo ""
echo "✅ Bootstrap scripts copied!"
