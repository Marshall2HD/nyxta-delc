# simple.sh
#!/usr/bin/env sh
set -eu

ARCH="armv7"                     # change to armv7 for Pi 3/Zero
ALPINE_VER="3.22.0"
TARBALL="alpine-rpi-${ALPINE_VER}-${ARCH}.tar.gz"
MIRROR="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER%.*}/releases/${ARCH}"

WORK=$(mktemp -d)
OVERLAY=$(mktemp -d)
trap 'rm -rf "$WORK" "$OVERLAY"' EXIT INT TERM

echo "→ downloading Alpine rootfs"
curl -#SL "$MIRROR/$TARBALL" | tar -xz -C "$WORK"


# ── interactive prompts ────────────────────────────────────────────────
# The script will exit gracefully on Ctrl+C thanks to the 'trap' command at the top.

# Set default values
DEFAULT_HOST="nyxta-apline.home.arpa"
DEFAULT_TZ="UTC"
DEFAULT_KEYMAP="us"

printf "FQDN (default: %s): " "$DEFAULT_HOST"; read -r HOST
HOST=${HOST:-$DEFAULT_HOST}

while true; do
    printf "Root password: "; read -s ROOTPW; echo
    printf "Verify password: "; read -s ROOTPW2; echo
    if [ "$ROOTPW" = "$ROOTPW2" ] && [ -n "$ROOTPW" ]; then
        break
    fi
    echo "Passwords do not match or are empty. Please try again."
done

printf "Timezone (default: %s): " "$DEFAULT_TZ"; read -r TZ
TZ=${TZ:-$DEFAULT_TZ}

printf "Keyboard layout (default: %s): " "$DEFAULT_KEYMAP"; read -r KEYMAP
KEYMAP=${KEYMAP:-$DEFAULT_KEYMAP}

echo "Paste your SOPS age key value (optional, press Enter to skip):"
read -r AGEKEY

echo "Paste your SSH public key (required for SSH access):"
read -r SSHKEY
if [ -z "$SSHKEY" ]; then
    echo "Warning: No SSH key provided. You may not be able to log in via SSH."
fi

printf "Add extra user? (y/N): "; read -r ADDUSR
ADDUSR=${ADDUSR:-n}
if [ "$ADDUSR" = "y" ]; then
  printf "Username: "; read -r USER
  while true; do
      printf "User password: "; read -s USRPW; echo
      printf "Verify password: "; read -s USRPW2; echo
      if [ "$USRPW" = "$USRPW2" ] && [ -n "$USRPW" ]; then
          break
      fi
      echo "Passwords do not match or are empty. Please try again."
  done
fi

printf "Target block device (e.g. /dev/sdX): "; read -r DEV
[ -b "$DEV" ] || { echo "✗ $DEV is not a block device"; exit 1; }
printf "‼  ALL DATA on $DEV will be DESTROYED – type YES to continue: "
read -r CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "aborted"; exit 1; }

# ── build overlay ──────────────────────────────────────────────────────
mkdir -p "$OVERLAY"/{etc,root/.ssh,root/.sops,etc/network/interfaces.d}

echo "$HOST"                    > "$OVERLAY/etc/hostname"
cat > "$OVERLAY/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   $HOST
EOF

echo "$TZ"                      > "$OVERLAY/etc/timezone"
ln -sf "/usr/share/zoneinfo/$TZ" "$OVERLAY/etc/localtime"
echo "keymap=\"$KEYMAP\""       > "$OVERLAY/etc/conf.d/keymaps"

echo "$SSHKEY"                  > "$OVERLAY/root/.ssh/authorized_keys"
chmod 600 "$OVERLAY/root/.ssh/authorized_keys"

cat > "$OVERLAY/etc/network/interfaces.d/eth0" <<EOF
auto eth0
iface eth0 inet dhcp
EOF

echo "$AGEKEY"                  > "$OVERLAY/root/.sops/age.key"
chmod 600 "$OVERLAY/root/.sops/age.key"

if [ "$ADDUSR" = "y" ]; then
  chroot "$WORK" apk add --no-cache sudo
  chroot "$WORK" addgroup "$USER" wheel
  chroot "$WORK" adduser -D -G wheel -s /bin/ash "$USER"
  echo "$USER:$USRPW" | chroot "$WORK" chpasswd
  mkdir -p "$OVERLAY/etc/sudoers.d"
  echo "%wheel ALL=(ALL) NOPASSWD: ALL" > "$OVERLAY/etc/sudoers.d/wheel"
fi

# ── merge overlay & enable services ────────────────────────────────────
cp -a "$OVERLAY/." "$WORK/"
chroot "$WORK" apk add --no-cache openssh chrony
chroot "$WORK" rc-update add sshd    default
chroot "$WORK" rc-update add chronyd default
echo "root:$ROOTPW" | chroot "$WORK" chpasswd

# ── wipe & partition target disk ───────────────────────────────────────
echo "→ wiping $DEV"
dd if=/dev/zero of="$DEV" bs=1M count=10 status=progress
sgdisk --zap-all "$DEV"
parted -s "$DEV" mklabel gpt mkpart primary ext4 1MiB 100%

echo "→ formatting ${DEV}1"
mkfs.ext4 -F "${DEV}1"

# ── copy prepared rootfs onto disk ─────────────────────────────────────
MNT=$(mktemp -d)
mount "${DEV}1" "$MNT"
echo "→ copying files (this can take a while)"
rsync -aHAX --info=progress2 "$WORK"/ "$MNT"/
umount "$MNT"
sync

echo "✓ finished – insert card and boot the Pi"