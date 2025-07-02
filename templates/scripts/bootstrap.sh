#!/bin/sh

# bootstrap.sh: Script to provision a new Alpine Linux system.

set -e # Exit on error

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Main Logic ---

# 1. Update Alpine
update_alpine() {
    info "Updating Alpine packages..."
    apk update
    apk upgrade
}

# 2. Install dependencies
install_deps() {
    info "Installing dependencies..."
    apk add curl sudo git
}

# 21.5 Set up chrony
setup_chrony() {
    info "Setting up chrony for time synchronization..."
    apk add chrony
    rc-update add chronyd default
    rc-service chronyd start
}

# 2. Install K0s, etc.
install_k0s() {
    info "Installing k0s..."
    curl -sSLf https://get.k0s.sh | sh
    k0s install controller --single
    k0s start
    
    # Wait for k0s to be ready
    info "Waiting for k0s to become ready..."
    sleep 60 # Give it some time to start up
    
    export KUBECONFIG=/var/lib/k0s/pki/admin.conf
    
    # Verify cluster is ready
    until k0s kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; do
      info "Waiting for node to be ready..."
      sleep 10
    done
    info "k0s cluster is ready."
}

# 3. Download repo
download_repo() {
    info "Cloning configuration repository..."
    if [ -d "/aether/nyxta-alpine" ]; then
        info "Removing existing repository to ensure a clean clone."
        rm -rf "/aether/nyxta-alpine"
    fi
    git clone https://github.com/Marshall2HD/nyxta-delc.git /aether/nyxta-alpine
}

# --- Script Execution ---
main() {
    info "Starting bootstrap process..."
    
    update_alpine
    install_deps
    setup_chrony
    install_k0s
    download_repo
    
    info "Bootstrap process complete."
    info "The system is now provisioned."

    # Disable this script from running again
    rm -- "$0"
}

main
