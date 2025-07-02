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
OS="" # Will be 'Linux' or 'Mac'

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

# --- OS-specific and Sudo-aware Functions ---

get_os() {
    case "$(uname -s)" in
        Linux*)     OS=Linux;;
        Darwin*)    OS=Mac;;
        *)          error "Unsupported operating system: $(uname -s)";;
    esac
}

check_deps() {
    info "Detected OS: $OS"
    
    # Common dependencies
    for cmd in curl git openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "$cmd is not installed. Please install it."
        fi
    done

    if [ "$OS" = "Linux" ]; then
        for cmd in parted mkfs.vfat lsblk sha256sum; do
             if ! command -v "$cmd" >/dev/null 2>&1; then
                error "$cmd is not installed. Please install it."
            fi
        done
    elif [ "$OS" = "Mac" ]; then
        if ! command -v "diskutil" >/dev/null 2>&1 || ! command -v "shasum" >/dev/null 2>&1; then
            error "macOS command line tools (diskutil, shasum) not found. Please install them."
        fi
    fi
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
    curl -# -L -O "$ALPINE_RPI_URL"
    curl -# -L -O "${ALPINE_RPI_URL}.sha256"
}

# 5. Verify the downloaded image
verify_image() {
    info "Verifying image checksum..."
    if [ "$OS" = "Mac" ]; then
        expected_hash=$(cut -d ' ' -f 1 "alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz.sha256")
        echo "$expected_hash  alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" | shasum -a 256 -c -
    else
        sha256sum -c "alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz.sha256"
    fi
    info "Checksum verified."
}

# 6. List disks
list_disks() {
    info "Available disks:"
    if [ "$OS" = "Mac" ]; then
        diskutil list external | grep -E '(\*|/dev/disk)'
    else
        lsblk -d -o NAME,SIZE,MODEL
    fi
}

# 7. & 8. Select disk
select_disk() {
    list_disks
    selected_disk=$(prompt "Enter the disk to write the image to (e.g., /dev/sda or /dev/disk2): ")
    if [ ! -b "$selected_disk" ] && [ ! -c "$selected_disk" ]; then
        error "Invalid disk selected: $selected_disk"
    fi
    if ! confirm "Are you sure you want to format and install to $selected_disk? THIS IS DESTRUCTIVE."; then
        error "Installation aborted by user."
    fi
    DISK="$selected_disk"
}

write_to_disk_and_configure() {
    info "Sudo access is required for disk operations."
    sudo -v || error "Sudo access failed. Aborting."

    if [ "$OS" = "Mac" ]; then
        write_to_disk_mac
    else
        write_to_disk_linux
    fi

    setup_boot
    configure_alpine
}

write_to_disk_mac() {
    info "Unmounting $DISK..."
    sudo diskutil unmountDisk "$DISK"

    info "Partitioning and formatting $DISK..."
    sudo diskutil partitionDisk "$DISK" 1 MBR FAT32 "ALPINE" "100%"

    MOUNT_POINT="/Volumes/ALPINE"
    info "Waiting for disk to mount at $MOUNT_POINT..."
    sleep 5 

    if [ ! -d "$MOUNT_POINT" ]; then
        error "Disk did not mount as expected at $MOUNT_POINT."
    fi

    info "Extracting Alpine tarball to $MOUNT_POINT..."
    sudo tar -xzf "alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" -C "$MOUNT_POINT"
    
    info "Alpine extracted."
}

write_to_disk_linux() {
    info "Partitioning and formatting $DISK..."
    sudo umount "${DISK}"* || true
    
    sudo parted -s "$DISK" mklabel msdos
    sudo parted -s -a optimal "$DISK" mkpart primary fat32 0% 100%
    sudo parted -s "$DISK" set 1 boot on

    PARTITION="${DISK}1"
    if [ ! -b "$PARTITION" ]; then
        PARTITION="${DISK}p1" # for NVMe drives
    fi
    
    info "Formatting partition $PARTITION as FAT32..."
    sudo mkfs.vfat -F 32 "$PARTITION"

    info "Mounting partition..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$PARTITION" "$MOUNT_POINT"

    info "Extracting Alpine tarball to $MOUNT_POINT..."
    sudo tar -xzf "alpine-rpi-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz" -C "$MOUNT_POINT"
    
    info "Alpine extracted."
}

# 13. Ensure boot directory is populated
setup_boot() {
    info "Setting up boot configuration..."
    echo "modules=loop,squashfs,sd-mod,usb-storage quiet console=tty1" | sudo tee "${MOUNT_POINT}/cmdline.txt" > /dev/null
    
    if [ ! -f "${MOUNT_POINT}/config.txt" ]; then
        sudo touch "${MOUNT_POINT}/config.txt"
    fi
    echo "kernel=boot/vmlinuz-rpi" | sudo tee -a "${MOUNT_POINT}/config.txt" > /dev/null
    echo "initramfs boot/initramfs-rpi" | sudo tee -a "${MOUNT_POINT}/config.txt" > /dev/null
}

# 14-26. Configuration
configure_alpine() {
    info "Configuring Alpine..."
    
    # 14. Hostname
    hostname=$(prompt "Enter hostname [nyxta-alpine]: ")
    echo "${hostname:-nyxta-alpine}" | sudo tee "${MOUNT_POINT}/etc/hostname" > /dev/null

    # 15. Timezone
    timezone=$(prompt "Enter timezone [America/New_York]: ")
    echo "${timezone:-America/New_York}" | sudo tee "${MOUNT_POINT}/etc/timezone" > /dev/null

    # 16. Keymap
    keymap=$(prompt "Enter keymap [us]: ")
    sudo mkdir -p "${MOUNT_POINT}/etc/keymaps"
    echo "${keymap:-us}" | sudo tee "${MOUNT_POINT}/etc/keymaps/default" > /dev/null

    # 17. Root password
    info "Setting root password. Enter a plaintext password to be hashed."
    info "WARNING: Leaving the password empty is a security risk."
    root_pass=$(prompt "Enter root password (or leave empty): ")
    if [ -n "$root_pass" ]; then
        hashed_pass=$(openssl passwd -6 "$root_pass")
        # Use a portable sed command for macOS compatibility
        sudo sed -i.bak "s|^root::|root:${hashed_pass}:|" "${MOUNT_POINT}/etc/shadow"
        sudo rm "${MOUNT_POINT}/etc/shadow.bak"
    else
        info "WARNING: Root password is not set."
    fi

    # 18-20. Optional user
    if confirm "Create an optional user?"; then
        opt_user=$(prompt "Enter username for optional user: ")
        if [ -n "$opt_user" ]; then
            opt_pass=$(prompt "Enter password for optional user: ")
            
            echo "${opt_user}:x:1000:1000:${opt_user}:/home/${opt_user}:/bin/ash" | sudo tee -a "${MOUNT_POINT}/etc/passwd" > /dev/null
            echo "${opt_user}:!:::" | sudo tee -a "${MOUNT_POINT}/etc/group" > /dev/null
            echo "${opt_user}:x:1000:" | sudo tee -a "${MOUNT_POINT}/etc/group" > /dev/null
            sudo mkdir -p "${MOUNT_POINT}/home/${opt_user}"
            sudo chown 1000:1000 "${MOUNT_POINT}/home/${opt_user}"
            
            if [ -n "$opt_pass" ]; then
                hashed_opt_pass=$(openssl passwd -6 "$opt_pass")
                echo "${opt_user}:${hashed_opt_pass}:$(date +%s):0:99999:7:::" | sudo tee -a "${MOUNT_POINT}/etc/shadow" > /dev/null
            else
                echo "${opt_user}:!::0:99999:7:::" | sudo tee -a "${MOUNT_POINT}/etc/shadow" > /dev/null
            fi

            sudo mkdir -p "${MOUNT_POINT}/etc/sudoers.d"
            echo "$opt_user ALL=(ALL) NOPASSWD: ALL" | sudo tee "${MOUNT_POINT}/etc/sudoers.d/${opt_user}" > /dev/null
            info "User $opt_user created and added to sudoers."
        fi
    fi

    # 20.5 & 21. SSH keys
    info "Configuring SSH access..."
    sudo mkdir -p "${MOUNT_POINT}/root/.ssh"
    sudo chmod 700 "${MOUNT_POINT}/root/.ssh"
    
    ssh_key=$(prompt "Enter authorized SSH key value (public key): ")
    if [ -n "$ssh_key" ]; then
        echo "$ssh_key" | sudo tee "${MOUNT_POINT}/root/.ssh/authorized_keys" > /dev/null
        if [ -n "$opt_user" ]; then
            sudo mkdir -p "${MOUNT_POINT}/home/${opt_user}/.ssh"
            echo "$ssh_key" | sudo tee "${MOUNT_POINT}/home/${opt_user}/.ssh/authorized_keys" > /dev/null
            sudo chown -R 1000:1000 "${MOUNT_POINT}/home/${opt_user}/.ssh"
        fi
        info "SSH key added."
    fi

    # 22. LBU overlay
    info "Configuring LBU..."
    sudo mkdir -p "${MOUNT_POINT}/etc/lbu"
    echo 'USE_OVERLAY="yes"' | sudo tee "${MOUNT_POINT}/etc/lbu/lbu.conf" > /dev/null

    # 23. LBU includes
    echo "/etc/hostname" | sudo tee "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    echo "/etc/hosts" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    echo "/etc/shadow" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    echo "/etc/passwd" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    echo "/etc/group" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    echo "/etc/ssh" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    echo "/root/.ssh" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    if [ -n "$opt_user" ]; then
        echo "/home/${opt_user}" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
        echo "/etc/sudoers.d/${opt_user}" | sudo tee -a "${MOUNT_POINT}/etc/lbu/include" > /dev/null
    fi

    # 24. Network
    info "Configuring network..."
    cat <<EOF | sudo tee "${MOUNT_POINT}/etc/network/interfaces" > /dev/null
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

    # 25. age.key
    age_key=$(prompt "Enter age.key value: ")
    if [ -n "$age_key" ]; then
        sudo mkdir -p "${MOUNT_POINT}/etc/age"
        echo "$age_key" | sudo tee "${MOUNT_POINT}/etc/age/key.txt" > /dev/null
        info "age.key saved."
    fi

    # 26. bootstrap.sh service
    info "Setting up bootstrap service..."
    sudo mkdir -p "${MOUNT_POINT}/etc/local.d"
    cat <<EOF | sudo tee "${MOUNT_POINT}/etc/local.d/bootstrap.start" > /dev/null
#!/bin/sh
curl -fsSL https://nyxta.run | sh
EOF
    sudo chmod +x "${MOUNT_POINT}/etc/local.d/bootstrap.start"
}

cleanup() {
    info "Cleaning up..."
    if [ -d "$MOUNT_POINT" ] && (mount | grep -q "$MOUNT_POINT" || (df -h | grep -q "$MOUNT_POINT" 2>/dev/null)); then
        info "Unmounting $MOUNT_POINT..."
        sudo umount "$MOUNT_POINT" || true
    fi
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    info "Done."
}

# --- Script Execution ---
trap cleanup EXIT

main() {
    get_os
    check_deps
    setup_temp_dir
    download_alpine
    verify_image
    select_disk
    write_to_disk_and_configure
    
    info "Build process complete. You can now use the SD card in your Raspberry Pi."
}

main
