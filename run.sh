#!/bin/sh
# Entry script for nyxta.run — decides which script to fetch

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

SCRIPT_URL="https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/refs/heads/main/run.sh"

TMP_SCRIPT=$(mktemp)
if ! curl -fsSL "${SCRIPT_URL}" -o "${TMP_SCRIPT}"; then
  echo "[!] Failed to download script: ${SCRIPT_NAME}" >&2
  exit 1
fi

# Execute the script. Redirect stdin from /dev/tty
# to ensure it can read user input interactively.
# We don't pass any arguments down to the child script.
sh "${TMP_SCRIPT}" < /dev/tty

rm "${TMP_SCRIPT}"