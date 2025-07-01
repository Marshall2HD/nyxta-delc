#!/bin/sh
#
# nyxta-bootstrap: Diskless Alpine + ZFS + GitOps K8s Node
# This script runs on the Pi at boot to configure the system.

set -e

# --- Configuration ---
ZFS_POOL="aether"
PERSISTENT_DIR="/mnt/${ZFS_POOL}"
K0S_DATA_DIR="${PERSISTENT_DIR}/k0s"
SOPS_AGE_KEY_FILE="${PERSISTENT_DIR}/secrets/age.key"

# GitOps Configuration
GITHUB_USER="Marshall2HD"
GITHUB_REPO="nyxta-delc"
GIT_BRANCH="main"
GIT_PATH_IN_REPO="./clusters/my-cluster" # Path where Flux will find its configs

# --- Helper Functions ---
log() {
  echo "[bootstrap] $1"
}

# --- Main Script ---

log "Starting Nyxta bootstrap process..."

# 1. Update Alpine
log "Updating Alpine packages..."
apk update
apk upgrade

# 2. Install Dependencies
log "Installing dependencies (zfs, k0s, flux)..."
apk add zfs zfs-lts curl sudo
apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing k0s

# 3. Configure and Import ZFS
log "Configuring ZFS..."
modprobe zfs
if ! zpool list | grep -q "${ZFS_POOL}"; then
  log "Importing ZFS pool '${ZFS_POOL}'..."
  zpool import -f -d /dev/disk/by-id "${ZFS_POOL}" || log "ZFS pool '${ZFS_POOL}' not found. Continuing without it."
fi

if zfs list | grep -q "${ZFS_POOL}"; then
  log "ZFS pool '${ZFS_POOL}' is available."
  mkdir -p "${PERSISTENT_DIR}"
  mount -t zfs "${ZFS_POOL}" "${PERSISTENT_DIR}"
else
  log "WARNING: ZFS pool not mounted. Persistent data will be lost on reboot."
  mkdir -p "${K0S_DATA_DIR}"
fi

# 4. Configure SOPS
log "Configuring SOPS..."
mkdir -p "$(dirname "${SOPS_AGE_KEY_FILE}")"
if [ -f "/media/mmcblk0p1/user-conf.yml" ]; then
    SOPS_AGE_KEY=$(grep 'sops_age_key:' /media/mmcblk0p1/user-conf.yml | cut -d' ' -f2-)
    if [ -n "$SOPS_AGE_KEY" ] && [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
        log "Saving SOPS_AGE_KEY to persistent storage."
        echo "$SOPS_AGE_KEY" > "$SOPS_AGE_KEY_FILE"
        chmod 0400 "$SOPS_AGE_KEY_FILE"
    fi
fi

# 5. Export SOPS Key File Path
if [ -f "$SOPS_AGE_KEY_FILE" ]; then
  export SOPS_AGE_KEY_FILE
  log "SOPS_AGE_KEY_FILE exported."
fi

# 6. Install and Configure k0s
log "Configuring k0s..."
if ! k0s status > /dev/null 2>&1; then
  log "Installing k0s controller..."
  k0s install controller --data-dir "${K0S_DATA_DIR}" --single
  k0s start
  log "Waiting for k0s to be ready..."
  sleep 60 # Give k0s time to start
else
  log "k0s is already running."
fi
export KUBECONFIG="/var/lib/k0s/pki/admin.conf"
mkdir -p "$HOME/.kube"
cp "$KUBECONFIG" "$HOME/.kube/config"

# 7. Install Flux CLI
if ! command -v flux > /dev/null; then
    log "Installing Flux CLI..."
    curl -s https://fluxcd.io/install.sh | sh
    export PATH=$PATH:$HOME/.fluxcd/bin
fi

# 8. Bootstrap Flux (Sync from Git)
log "Bootstrapping Flux..."
if [ -z "$GITHUB_TOKEN" ]; then
  log "ERROR: GITHUB_TOKEN environment variable is not set. Cannot bootstrap Flux."
  exit 1
fi

flux bootstrap github \
  --owner="${GITHUB_USER}" \
  --repository="${GITHUB_REPO}" \
  --branch="${GIT_BRANCH}" \
  --path="${GIT_PATH_IN_REPO}" \
  --personal \
  --token-auth

log "Flux bootstrap complete. Cluster state will now be managed from Git."

# 9. Ensure self-updating init script
log "Configuring self-updating init script for next boot..."
install -Dm755 /templates/scripts/bootstrap.sh /etc/init.d/nyxta-init
rc-update add nyxta-init default || true
lbu add /etc/init.d/nyxta-init
lbu add /etc/runlevels/default/nyxta-init
lbu commit -d

log "Bootstrap finished successfully."