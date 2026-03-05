#!/bin/bash
# Run Android APK on Firebase Test Lab using Google Cloud SDK inside Docker.
# All operations run inside Docker — no gcloud installation on host required.
#
# Prerequisites:
#   1. Firebase project created at console.firebase.google.com
#   2. Service account JSON key at: ~/Desktop/MAIN/kalvin/testcase_and_creds/service-account-key.json
#      - Go to GCP Console → IAM → Service Accounts → Create → Editor role → Download JSON
#   3. APK built at: build/pockr-release.apk  (or build/pockr-debug.apk)
#
# Usage:
#   ./scripts/firebase_test.sh <gcp-project-id> [device] [android-version]
#
# Examples:
#   ./scripts/firebase_test.sh my-firebase-project
#   ./scripts/firebase_test.sh my-firebase-project Pixel6 31
#
# Available devices: run with --list-devices flag
#   ./scripts/firebase_test.sh my-firebase-project --list-devices

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GCP_PROJECT="${1}"
DEVICE="${2:-Pixel6}"
ANDROID_VERSION="${3:-31}"
APK="${4:-${PROJECT_ROOT}/build/pockr-release.apk}"
# Fall back to debug build if release not found
if [ ! -f "${APK}" ]; then
  APK="${PROJECT_ROOT}/build/pockr-debug.apk"
fi
KEY_FILE="${HOME}/Desktop/MAIN/kalvin/testcase_and_creds/service-account-key.json"

if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is required."
  exit 1
fi

# List available devices
if [ "${2}" = "--list-devices" ]; then
  echo "=== Available Firebase Test Lab devices ==="
  docker run --rm \
    --platform linux/amd64 \
    gcr.io/google.com/cloudsdktool/google-cloud-cli:stable \
    gcloud firebase test android models list
  exit 0
fi

if [ -z "${GCP_PROJECT}" ]; then
  echo "Usage: $0 <gcp-project-id> [device] [android-version]"
  echo "       $0 <gcp-project-id> --list-devices"
  exit 1
fi

if [ ! -f "${KEY_FILE}" ]; then
  echo "ERROR: Service account key not found at: ${KEY_FILE}"
  echo ""
  echo "To create one:"
  echo "  1. Go to https://console.cloud.google.com/iam-admin/serviceaccounts"
  echo "  2. Create a service account with Editor role"
  echo "  3. Download the JSON key"
  echo "  4. Save it as: ${KEY_FILE}"
  exit 1
fi

if [ ! -f "${APK}" ]; then
  echo "ERROR: APK not found at: ${APK}"
  echo "Run ./scripts/build_apk.sh first."
  exit 1
fi

echo "=== Firebase Test Lab ==="
echo "Project : ${GCP_PROJECT}"
echo "Device  : ${DEVICE} (Android ${ANDROID_VERSION})"
echo "APK     : $(du -sh ${APK} | cut -f1)"
echo ""

docker run --rm \
  --platform linux/amd64 \
  -v "${APK}:/app.apk:ro" \
  -v "${KEY_FILE}:/creds.json:ro" \
  -e "GCP_PROJECT=${GCP_PROJECT}" \
  -e "DEVICE=${DEVICE}" \
  -e "ANDROID_VERSION=${ANDROID_VERSION}" \
  gcr.io/google.com/cloudsdktool/google-cloud-cli:stable \
  bash -c '
set -e

echo "Authenticating with service account..."
gcloud auth activate-service-account --key-file=/creds.json --quiet
gcloud config set project "${GCP_PROJECT}" --quiet

echo ""
echo "Enabling required APIs..."
gcloud services enable testing.googleapis.com --quiet 2>/dev/null || true
gcloud services enable toolresults.googleapis.com --quiet 2>/dev/null || true

echo ""
echo "Starting robo test on ${DEVICE} (Android ${ANDROID_VERSION})..."
echo "Results will appear at: https://console.firebase.google.com/project/${GCP_PROJECT}/testlab"
echo ""

gcloud config set core/http_timeout 600 --quiet

gcloud firebase test android run \
  --app=/app.apk \
  --device "model=${DEVICE},version=${ANDROID_VERSION},locale=en,orientation=portrait" \
  --timeout 600s \
  --type robo

echo ""
echo "=== Test Complete ==="
echo "View detailed results at:"
echo "  https://console.firebase.google.com/project/${GCP_PROJECT}/testlab"
' 2>&1