#!/bin/sh
#
# nyxta-simple: Headless Alpine Pi Image Builder
#
# This script is designed to be run on your laptop or desktop.
# It prepares a bootable Alpine Linux SD card for a Raspberry Pi.

set -e

# --- Configuration ---
ALPINE_VERSION="3.22.0" # Check for the latest version at https://alpinelinux.org/downloads/
ALPINE_IMAGE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/armv7/alpine-rpi-${ALPINE_VERSION}-armv7.tar.gz"
IMAGE_FILE="alpine-rpi.tar.gz"
MOUNT_POINT=$(mktemp -d)

# --- Helper Functions ---
cleanup() {
  set +e
  echo "--- Cleaning up ---"
  if [ -d "$MOUNT_POINT" ]; then
    DEVICE_IDENTIFIER=$(df "$MOUNT_POINT" | awk 'NR==2 {print $1}')
    if [ -n "$DEVICE_IDENTIFIER" ]; then
        DISK_NAME=$(echo "$DEVICE_IDENTIFIER" | sed 's/s[0-9]*$//')
        echo "Unmounting $MOUNT_POINT..."
        umount "$MOUNT_POINT"
        echo "Ejecting $DISK_NAME..."
        diskutil eject "$DISK_NAME"
    fi
  fi
  rm -rf "$MOUNT_POINT"
  rm -f "$IMAGE_FILE"
  echo "Cleanup complete."
}
trap cleanup EXIT

# --- Main Script ---

# 1. Download Alpine Image
if [ ! -f "$IMAGE_FILE" ]; then
  echo "--- Downloading Alpine Linux for Raspberry Pi (aarch64) ---"
  curl -L "$ALPINE_IMAGE_URL" -o "$IMAGE_FILE"
  
  echo "--- Verifying checksum ---"
  # Download the checksum file
  curl -L "${ALPINE_IMAGE_URL}.sha256" -o "${IMAGE_FILE}.sha256"
  
  # Verify the checksum
  if ! shasum -a 256 -c "${IMAGE_FILE}.sha256"; then
    echo "[!] Checksum validation failed. Aborting." >&2
    rm "$IMAGE_FILE" "${IMAGE_FILE}.sha256"
    exit 1
  fi
  echo "--- Checksum verified ---"
  rm "${IMAGE_FILE}.sha256"

else
  echo "--- Alpine image already downloaded ---"
fi

# 2. Select Disk
echo "--- Please select the disk to write to ---"
diskutil list external
echo "Enter the disk identifier (e.g., /dev/disk4):"
read -r DISK
if [ -z "$DISK" ]; then
  echo "No disk selected. Aborting."
  exit 1
fi

echo "WARNING: This will erase all data on $DISK. Are you sure? (y/N)"
read -r CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "Aborting."
  exit 1
fi

# 3. Burn Image
echo "--- Unmounting disk $DISK before writing ---"
diskutil unmountDisk "$DISK"
echo "--- Writing image to $DISK (this may take a while) ---"
# We don't use dd, we extract directly to the disk which should be formatted as FAT32
# This is the standard Alpine diskless mode setup.
tar -xzf "$IMAGE_FILE" -C "$MOUNT_POINT" --strip-components=0
diskutil unmountDisk "$DISK"
echo "Please format the SD card to FAT32 using Disk Utility and name it 'NYXTA'."
echo "Press enter when you are ready to continue..."
read -r
# The SD card is now expected to be mounted at /Volumes/NYXTA
MOUNT_POINT="/Volumes/NYXTA"
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Mount point /Volumes/NYXTA not found. Aborting."
    exit 1
fi
tar -xzf "$IMAGE_FILE" -C "$MOUNT_POINT" --strip-components=0


# 5. Prompt for configuration
echo "--- Configuring the system ---"
printf "Enter new root password: "
read -r ROOT_PASSWORD
printf "Enter hostname (e.g., nyxta-pi): "
read -r HOSTNAME
printf "Enter SSH public key (paste content or provide a URL like https://github.com/user.keys): "
read -r SSH_KEY
printf "Enter your SOPS AGE private key (it will be stored on the boot partition): "
read -r SOPS_AGE_KEY

# 6. Inject configuration
echo "--- Injecting configuration files ---"

# Create user-conf.yml for Alpine's setup script
cat > "${MOUNT_POINT}/user-conf.yml" <<EOF
# user-conf.yml
hostname: ${HOSTNAME}
password: ${ROOT_PASSWORD}
ssh_key: "${SSH_KEY}"
sops_age_key: "${SOPS_AGE_KEY}"
EOF

# Create the init script
cat > "${MOUNT_POINT}/nyxta-init.sh" <<EOF
#!/bin/sh
# This script runs on first boot to finalize setup.
apk add curl
curl -fsSL https://nyxta.run | sh
EOF

# Create an overlay to run our script
cat > "${MOUNT_POINT}/apkovl-nyxta.sh" <<EOF
#!/bin/sh
# Create the OpenRC init script
cat > /etc/init.d/nyxta-init <<'INIT_SCRIPT'
#!/sbin/openrc-run
command="/usr/local/bin/nyxta-bootstrap.sh"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
    after networking
}
INIT_SCRIPT

chmod +x /etc/init.d/nyxta-init

# Copy bootstrap script
cp /media/mmcblk0p1/nyxta-bootstrap.sh /usr/local/bin/nyxta-bootstrap.sh
chmod +x /usr/local/bin/nyxta-bootstrap.sh

# Enable the service
rc-update add nyxta-init default

# Persist changes
lbu commit -d
EOF
chmod +x "${MOUNT_POINT}/apkovl-nyxta.sh"

echo "--- Configuration complete ---"

# 7. Unmount
# The cleanup function will handle unmounting and ejecting.
echo "--- Setup finished. The SD card can now be safely removed. ---"