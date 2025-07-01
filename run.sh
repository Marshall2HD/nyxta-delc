#!/bin/sh
# Entry script for nyxta.run — decides which script to fetch

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- OS Detection ---
OS_TYPE="unknown"
if [ -f /etc/alpine-release ]; then
    OS_TYPE="alpine"
elif [ "$(uname)" = "Darwin" ]; then
    OS_TYPE="macos"
fi

# --- Script Selection ---
SCRIPT_NAME="bootstrap.sh"
if [ "$1" = "--simple" ]; then
  SCRIPT_NAME="simple.sh"
fi

# --- Environment Validation ---
if [ "$OS_TYPE" = "macos" ] && [ "$SCRIPT_NAME" = "bootstrap.sh" ]; then
    echo "[!] The default bootstrap script is for Alpine Linux, not macOS." >&2
    echo "    To create a bootable SD card on your Mac, please run:" >&2
    echo "    curl -fsSL https://nyxta.run | sh -s -- --simple" >&2
    exit 1
fi

if [ "$OS_TYPE" = "alpine" ] && [ "$SCRIPT_NAME" = "simple.sh" ]; then
    echo "[!] The simple script is for preparing an SD card on macOS, not for running on an Alpine system." >&2
    echo "    The default bootstrap script should run automatically on boot." >&2
    exit 1
fi

REPO_URL="https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/main"
SCRIPT_URL="${REPO_URL}/templates/scripts/${SCRIPT_NAME}"
SHASUM_URL="${REPO_URL}/shasum.txt"

TMP_SCRIPT=$(mktemp)
if ! curl -fsSL "${SCRIPT_URL}" -o "${TMP_SCRIPT}"; then
  echo "[!] Failed to download script: ${SCRIPT_NAME}" >&2
  exit 1
fi

EXPECTED_SHA=$(curl -fsSL "${SHASUM_URL}" | grep "${SCRIPT_NAME}" | awk '{print $1}')
if [ -z "${EXPECTED_SHA}" ]; then
  echo "[!] Failed to get expected SHA for ${SCRIPT_NAME}" >&2
  rm "${TMP_SCRIPT}"
  exit 1
fi

ACTUAL_SHA=""
if command_exists sha256sum; then
  ACTUAL_SHA=$(sha256sum "${TMP_SCRIPT}" | awk '{print $1}')
elif command_exists shasum; then
  ACTUAL_SHA=$(shasum -a 256 "${TMP_SCRIPT}" | awk '{print $1}')
else
  echo "[!] Neither sha256sum nor shasum found. Cannot verify script integrity." >&2
  rm "${TMP_SCRIPT}"
  exit 1
fi

if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "[!] SHA mismatch for ${SCRIPT_NAME}" >&2
  echo "    Expected: ${EXPECTED_SHA}" >&2
  echo "    Actual:   ${ACTUAL_SHA}" >&2
  rm "${TMP_SCRIPT}"
  exit 1
fi

# Execute the script, but redirect stdin from /dev/tty
# to ensure it can read user input interactively.
sh "${TMP_SCRIPT}" "$@" < /dev/tty

rm "${TMP_SCRIPT}"