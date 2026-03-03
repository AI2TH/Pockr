#!/bin/bash
# Verify all assets are present and valid.
# All checks run inside a Docker container — no host-side tools required.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/android/app/src/main/assets"

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required but not found."
    exit 1
fi

echo "=== Asset Verification (via Docker) ==="

# Run all verification logic inside Docker where tools (file, stat, du) behave
# consistently regardless of the host OS (macOS vs Linux).
EXIT_CODE=$(docker run --rm \
    --platform linux/amd64 \
    -v "${ASSETS_DIR}:/assets:ro" \
    debian:bookworm-slim \
    bash -c '
set -e
apt-get update -qq
apt-get install -y -qq file binutils 2>/dev/null

ERRORS=0
WARNINGS=0

# ------------------------------------------------------------------ directories
echo "Checking directories..."
for DIR in qemu vm bootstrap; do
    if [ -d "/assets/$DIR" ]; then
        echo "  OK  $DIR/"
    else
        echo "  ERR $DIR/ — missing"
        ERRORS=$((ERRORS+1))
    fi
done

echo ""

# ------------------------------------------------------------------ QEMU binaries
echo "Checking QEMU binaries..."

check_binary() {
    local path="$1" name="$2" min_bytes="$3"
    if [ ! -f "$path" ]; then
        echo "  ERR $name — NOT FOUND"
        ERRORS=$((ERRORS+1))
        return
    fi
    local size
    size=$(stat -c%s "$path")
    local mb=$(( size / 1024 / 1024 ))
    if [ "$size" -lt "$min_bytes" ]; then
        echo "  WARN $name — too small (${mb}MB)"
        WARNINGS=$((WARNINGS+1))
    else
        echo "  OK  $name — ${mb}MB"
    fi
    local ft
    ft=$(file "$path")
    if echo "$ft" | grep -q "ELF 64-bit.*aarch64"; then
        echo "       arch: aarch64 ✓"
    else
        echo "       WARN: $ft"
        WARNINGS=$((WARNINGS+1))
    fi
}

check_binary /assets/qemu/qemu-system-aarch64 "qemu-system-aarch64" $((10*1024*1024))
check_binary /assets/qemu/qemu-img             "qemu-img"             $((1*1024*1024))

echo ""

# ------------------------------------------------------------------ Alpine image
echo "Checking Alpine Linux image..."
BASE=/assets/vm/base.qcow2.gz
if [ ! -f "$BASE" ]; then
    echo "  ERR base.qcow2.gz — NOT FOUND"
    ERRORS=$((ERRORS+1))
else
    size=$(stat -c%s "$BASE")
    mb=$(( size / 1024 / 1024 ))
    if [ "$size" -lt $((30*1024*1024)) ]; then
        echo "  WARN base.qcow2.gz — too small (${mb}MB)"
        WARNINGS=$((WARNINGS+1))
    elif [ "$size" -gt $((120*1024*1024)) ]; then
        echo "  WARN base.qcow2.gz — very large (${mb}MB)"
        WARNINGS=$((WARNINGS+1))
    else
        echo "  OK  base.qcow2.gz — ${mb}MB"
    fi
    if file "$BASE" | grep -q "gzip"; then
        echo "       format: gzip ✓"
    else
        echo "       WARN: not gzip"
        WARNINGS=$((WARNINGS+1))
    fi
fi

echo ""

# ------------------------------------------------------------------ bootstrap
echo "Checking bootstrap scripts..."
for f in api_server.py init_bootstrap.sh requirements.txt; do
    path="/assets/bootstrap/$f"
    if [ ! -f "$path" ]; then
        echo "  ERR  $f — NOT FOUND"
        ERRORS=$((ERRORS+1))
    else
        sz=$(stat -c%s "$path")
        if [ "$sz" -eq 0 ]; then
            echo "  ERR  $f — EMPTY"
            ERRORS=$((ERRORS+1))
        else
            echo "  OK   $f — ${sz} bytes"
        fi
    fi
done

echo ""

# ------------------------------------------------------------------ checksums
echo "Checking checksums.txt..."
if [ -f /assets/checksums.txt ]; then
    n=$(wc -l < /assets/checksums.txt)
    echo "  OK  checksums.txt — ${n} entries"
else
    echo "  WARN checksums.txt missing — run generate_checksums.sh"
    WARNINGS=$((WARNINGS+1))
fi

echo ""

# ------------------------------------------------------------------ sizes
echo "=== Size Summary ==="
[ -d /assets/qemu ]      && echo "QEMU binaries : $(du -sh /assets/qemu      | cut -f1)"
[ -d /assets/vm ]        && echo "VM image      : $(du -sh /assets/vm        | cut -f1)"
[ -d /assets/bootstrap ] && echo "Bootstrap     : $(du -sh /assets/bootstrap | cut -f1)"
echo "Total         : $(du -sh /assets | cut -f1)"

echo ""
echo "Errors  : $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "RESULT: ALL_GOOD"
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo "RESULT: WARNINGS"
    exit 2
else
    echo "RESULT: ERRORS"
    exit 1
fi
'; EXIT_CODE=$?)

echo ""
case $EXIT_CODE in
    0) echo "✅  All assets verified — ready to build APK." ;;
    2) echo "⚠️   Assets present with warnings — check output above." ;;
    *)
        echo "❌  Asset verification FAILED."
        echo "    Run scripts/setup_assets.sh to acquire missing assets."
        exit 1
        ;;
esac
