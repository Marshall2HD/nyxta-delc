#!/bin/sh

# build.sh: Script to create a customized Alpine Linux image for Raspberry Pi.

set -e # Exit on error

# --- Configuration ---
ALPINE_VERSION="3.22.0"
ALPINE_ARCH="armv7"
ALPINE_RPI_URL="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/${ALPINE_ARCH}/alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
REPO_URL="https://github.com/Marshall2HD/nyxta-delc.git"
TEMP_DIR=""
MOUNT_POINT="/mnt/alpine"

# --- Helper Functions ---
info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

prompt() {
    printf "[PROMPT] %s" "$1"
    read -r response
    echo "$response"
}

confirm() {
    while true; do
        read -p "[CONFIRM] $1 [y/n] " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# --- Main Logic ---

# 1. Create a temp directory for the build.
setup_temp_dir() {
    info "Creating temporary directory..."
    TEMP_DIR=$(mktemp -d)
    info "Temporary directory created at $TEMP_DIR"
    cd "$TEMP_DIR"
}

# 3. & 4. Download Alpine image and hash
download_alpine() {
    info "Downloading Alpine Linux for RPi..."
    wget -q --show-progress "$ALPINE_RPI_URL"
    wget -q --show-progress "${ALPINE_RPI_URL}.sha256"
}

# 5. Verify the downloaded image
verify_image() {
    info "Verifying image checksum..."
    sha256sum -c "alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz.sha256"
    info "Checksum verified."
}

# 6. List disks
list_disks() {
    info "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
}

# 7. & 8. Select disk
select_disk() {
    list_disks
    selected_disk=$(prompt "Enter the disk to write the image to (e.g., /dev/sda): ")
    if [ ! -b "$selected_disk" ]; then
        error "Invalid disk selected: $selected_disk"
    fi
    if ! confirm "Are you sure you want to format and install to $selected_disk? THIS IS DESTRUCTIVE."; then
        error "Installation aborted by user."
    fi
    DISK="$selected_disk"
}

# 9. & 10. Format and write image
install_to_disk() {
    info "Partitioning and formatting $DISK..."
    # Unmount any existing partitions
    umount "${DISK}"* || true
    
    # Create a new partition table and a single partition
    parted -s "$DISK" mklabel msdos
    parted -s -a optimal "$DISK" mkpart primary fat32 0% 100%
    parted -s "$DISK" set 1 boot on

    # Get partition name
    PARTITION="${DISK}1"
    if [ ! -b "$PARTITION" ]; then
        PARTITION="${DISK}p1" # for NVMe drives
    fi
    
    info "Formatting partition $PARTITION as FAT32..."
    mkfs.vfat -F 32 "$PARTITION"

    info "Mounting partition..."
    mkdir -p "$MOUNT_POINT"
    mount "$PARTITION" "$MOUNT_POINT"

    info "Extracting Alpine tarball to $MOUNT_POINT..."
    tar -xzf "alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" -C "$MOUNT_POINT"
    
    info "Alpine extracted."
}

# 13. Ensure boot directory is populated
setup_boot() {
    info "Setting up boot configuration..."
    echo "modules=loop,squashfs,sd-mod,usb-storage quiet console=tty1" > "${MOUNT_POINT}/cmdline.txt"
    
    if [ ! -f "${MOUNT_POINT}/config.txt" ]; then
        touch "${MOUNT_POINT}/config.txt"
    fi
    echo "kernel=boot/vmlinuz-rpi" >> "${MOUNT_POINT}/config.txt"
    echo "initramfs boot/initramfs-rpi" >> "${MOUNT_POINT}/config.txt"
}

# 14-26. Configuration
configure_alpine() {
    info "Configuring Alpine..."
    
    # 14. Hostname
    hostname=$(prompt "Enter hostname [nyxta-alpine]: ")
    echo "${hostname:-nyxta-alpine}" > "${MOUNT_POINT}/etc/hostname"

    # 15. Timezone
    timezone=$(prompt "Enter timezone [America/New_York]: ")
    echo "${timezone:-America/New_York}" > "${MOUNT_POINT}/etc/timezone"

    # 16. Keymap
    keymap=$(prompt "Enter keymap [us]: ")
    echo "${keymap:-us}" > "${MOUNT_POINT}/etc/keymaps/default"

    # 17. Root password
    info "Setting root password. Enter a plaintext password to be hashed."
    info "WARNING: Leaving the password empty is a security risk."
    root_pass=$(prompt "Enter root password (or leave empty): ")
    if [ -n "$root_pass" ]; then
        hashed_pass=$(openssl passwd -6 "$root_pass")
        sed -i "s|^root::|root:${hashed_pass}:|" "${MOUNT_POINT}/etc/shadow"
    else
        info "WARNING: Root password is not set."
    fi

    # 18-20. Optional user
    if confirm "Create an optional user?"; then
        opt_user=$(prompt "Enter username for optional user: ")
        if [ -n "$opt_user" ]; then
            opt_pass=$(prompt "Enter password for optional user: ")
            
            echo "${opt_user}:x:1000:1000:${opt_user}:/home/${opt_user}:/bin/ash" >> "${MOUNT_POINT}/etc/passwd"
            echo "${opt_user}:!:::" >> "${MOUNT_POINT}/etc/group"
            echo "${opt_user}:x:1000:" >> "${MOUNT_POINT}/etc/group"
            mkdir -p "${MOUNT_POINT}/home/${opt_user}"
            chown 1000:1000 "${MOUNT_POINT}/home/${opt_user}"
            
            if [ -n "$opt_pass" ]; then
                hashed_opt_pass=$(openssl passwd -6 "$opt_pass")
                echo "${opt_user}:${hashed_opt_pass}:$(date +%s):0:99999:7:::" >> "${MOUNT_POINT}/etc/shadow"
            else
                echo "${opt_user}:!::0:99999:7:::" >> "${MOUNT_POINT}/etc/shadow"
            fi

            mkdir -p "${MOUNT_POINT}/etc/sudoers.d"
            echo "$opt_user ALL=(ALL) NOPASSWD: ALL" > "${MOUNT_POINT}/etc/sudoers.d/${opt_user}"
            info "User $opt_user created and added to sudoers."
        fi
    fi

    # 20.5 & 21. SSH keys
    info "Configuring SSH access..."
    mkdir -p "${MOUNT_POINT}/root/.ssh"
    chmod 700 "${MOUNT_POINT}/root/.ssh"
    
    ssh_key=$(prompt "Enter authorized SSH key value (public key): ")
    if [ -n "$ssh_key" ]; then
        echo "$ssh_key" > "${MOUNT_POINT}/root/.ssh/authorized_keys"
        if [ -n "$opt_user" ]; then
            mkdir -p "${MOUNT_POINT}/home/${opt_user}/.ssh"
            echo "$ssh_key" > "${MOUNT_POINT}/home/${opt_user}/.ssh/authorized_keys"
            chown -R 1000:1000 "${MOUNT_POINT}/home/${opt_user}/.ssh"
        fi
        info "SSH key added."
    fi

    # 22. LBU overlay
    info "Configuring LBU..."
    mkdir -p "${MOUNT_POINT}/etc/lbu"
    echo 'USE_OVERLAY="yes"' > "${MOUNT_POINT}/etc/lbu/lbu.conf"

    # 23. LBU includes
    echo "/etc/hostname" > "${MOUNT_POINT}/etc/lbu/include"
    echo "/etc/hosts" >> "${MOUNT_POINT}/etc/lbu/include"
    echo "/etc/shadow" >> "${MOUNT_POINT}/etc/lbu/include"
    echo "/etc/passwd" >> "${MOUNT_POINT}/etc/lbu/include"
    echo "/etc/group" >> "${MOUNT_POINT}/etc/lbu/include"
    echo "/etc/ssh" >> "${MOUNT_POINT}/etc/lbu/include"
    echo "/root/.ssh" >> "${MOUNT_POINT}/etc/lbu/include"
    if [ -n "$opt_user" ]; then
        echo "/home/${opt_user}" >> "${MOUNT_POINT}/etc/lbu/include"
        echo "/etc/sudoers.d/${opt_user}" >> "${MOUNT_POINT}/etc/lbu/include"
    fi

    # 24. Network
    info "Configuring network..."
    cat <<EOF > "${MOUNT_POINT}/etc/network/interfaces"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

    # 25. age.key
    age_key=$(prompt "Enter age.key value: ")
    if [ -n "$age_key" ]; then
        mkdir -p "${MOUNT_POINT}/etc/age"
        echo "$age_key" > "${MOUNT_POINT}/etc/age/key.txt"
        info "age.key saved."
    fi

    # 26. bootstrap.sh service
    info "Setting up bootstrap service..."
    mkdir -p "${MOUNT_POINT}/etc/local.d"
    cat <<EOF > "${MOUNT_POINT}/etc/local.d/bootstrap.start"
#!/bin/sh
curl -fsSL https://nyxta.run | sh
EOF
    chmod +x "${MOUNT_POINT}/etc/local.d/bootstrap.start"
}

cleanup() {
    info "Cleaning up..."
    if [ -d "$MOUNT_POINT" ]; then
        umount "$MOUNT_POINT" || true
    fi
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    info "Done."
}

# --- Script Execution ---
trap cleanup EXIT

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root."
    fi
    
    for cmd in wget parted mkfs.vfat git openssl sha256sum lsblk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "$cmd is not installed. Please install it."
        fi
    done

    setup_temp_dir
    download_alpine
    verify_image
    select_disk
    install_to_disk
    setup_boot
    configure_alpine
    
    info "Build process complete. You can now use the SD card in your Raspberry Pi."
}

main
