#!/bin/sh

# install.sh: Entry point for nyxta-delc installation.

set -e

# --- Configuration ---
BUILD_SCRIPT_URL="https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/main/templates/scripts/build.sh"
BOOTSTRAP_SCRIPT_URL="https://raw.githubusercontent.com/Marshall2HD/nyxta-delc/main/templates/scripts/bootstrap.sh"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Main Logic ---
main() {
    if [ "$1" = "--build" ]; then
        info "Starting build process..."
        curl -fsSL "$BUILD_SCRIPT_URL" | sh -s -- "$@"
    else
        info "Starting bootstrap process..."
        # This part is intended to be run on the Alpine machine itself.
        # The primary use case is via the local.d service setup in build.sh
        curl -fsSL "$BOOTSTRAP_SCRIPT_URL" | sh -s -- "$@"
    fi
}

main "$@"
