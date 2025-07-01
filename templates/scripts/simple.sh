#!/bin/sh
#
# nyxta-simple: Headless Alpine Pi Image Builder
#
# This script is designed to be run on your laptop or desktop.
# It prepares a bootable Alpine Linux SD card for a Raspberry Pi.

set -e

# --- Configuration ---
ALPINE_VERSION="3.22.0"
ALPINE_IMAGE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/armv7/alpine-rpi-${ALPINE_VERSION}-armv7.tar.gz"
IMAGE_FILE=$(basename "$ALPINE_IMAGE_URL")
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
  echo "--- Version: 1.0.1                                      ---"
  echo "--- Downloading Alpine Linux for Raspberry Pi (armv764) ---"
  curl -L -O "$ALPINE_IMAGE_URL"
  
  echo "--- Verifying checksum ---"
  # Download the checksum file
  curl -L -O "${ALPINE_IMAGE_URL}.sha256"
  
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
read -r DISK < /dev/tty
if [ -z "$DISK" ]; then
  echo "No disk selected. Aborting."
  exit 1
fi

echo "WARNING: This will erase all data on $DISK. Are you sure? (y/N)"
read -r CONFIRM < /dev/tty
if [ "$CONFIRM" != "y" ]; then
  echo "Aborting."
  exit 1
fi

# 3. Burn Image
echo "--- Unmounting disk $DISK before writing ---"
diskutil unmountDisk "$DISK"
echo "--- Formatting disk $DISK as FAT32 with name NYXTA ---"
diskutil eraseDisk FAT32 NYXTA MBRFormat "$DISK"

echo "--- Writing image to $DISK (this may take a while) ---"
# The SD card is now expected to be mounted at /Volumes/NYXTA
MOUNT_POINT="/Volumes/NYXTA"
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Mount point /Volumes/NYXTA not found after formatting. Aborting."
    exit 1
fi
tar -xzf "$IMAGE_FILE" -C "$MOUNT_POINT" --strip-components=0


# 5. Prompt for configuration
echo "--- Configuring the system ---"

printf "Enter new root password (input will be hidden): "
stty -echo
read -r ROOT_PASSWORD < /dev/tty
stty echo
printf "\n"

printf "Enter hostname (e.g., nyxta-pi, not a fully qualified domain name): "
read -r HOSTNAME < /dev/tty

printf "Enter SSH public key (paste content or provide a URL like https://github.com/user.keys): "
read -r SSH_KEY < /dev/tty
if echo "$SSH_KEY" | grep -q '^https://'; then
  SSH_KEY=$(curl -fsSL "$SSH_KEY")
fi

printf "Enter your SOPS AGE private key (the long string starting with 'AGE-SECRET-KEY-'): "
read -r SOPS_AGE_KEY < /dev/tty

# Ask to create a new user
printf "Do you want to create a new non-root user? (y/N): "
read -r CREATE_USER_CONFIRM < /dev/tty
if [ "$CREATE_USER_CONFIRM" = "y" ]; then
    printf "Enter username for the new user: "
    read -r NEW_USERNAME < /dev/tty
    printf "Enter password for %s (input will be hidden): " "$NEW_USERNAME"
    stty -echo
    read -r NEW_USER_PASSWORD < /dev/tty
    stty echo
    printf "\n"
fi

# 6. Inject configuration
echo "--- Injecting configuration files ---"

# Create user-conf.yml for Alpine's setup script
cat > "${MOUNT_POINT}/user-conf.yml" <<EOF
# user-conf.yml
hostname: ${HOSTNAME}
password: ${ROOT_PASSWORD}
ssh_key: "${SSH_KEY}"
sops_age_key: "${SOPS_AGE_KEY}"
new_username: "${NEW_USERNAME}"
new_user_password: "${NEW_USER_PASSWORD}"
EOF

# Create the init script
cat > "${MOUNT_POINT}/nyxta-init.sh" <<EOF
#!/bin/sh
# This script runs on first boot to finalize setup.
apk add curl
curl -fsSL https://nyxta.run | sh
EOF

# Make nyxta-init.sh run on first boot via OpenRC local.d
mkdir -p "${MOUNT_POINT}/etc/local.d"
cat > "${MOUNT_POINT}/etc/local.d/nyxta-init.start" <<LOCAL_EOF
#!/bin/sh
sh /nyxta-init.sh
LOCAL_EOF

chmod +x "${MOUNT_POINT}/etc/local.d/nyxta-init.start"
ln -sf /etc/init.d/local "${MOUNT_POINT}/etc/runlevels/default/local"

echo "--- Configuration complete ---"

# 7. Unmount
# The cleanup function will handle unmounting and ejecting.
echo "--- Setup finished. The SD card can now be safely removed. ---"