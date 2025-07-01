# simple.sh
#!/usr/bin/env sh
set -eu

ARCH="aarch64"                     # change to armv7 for Pi 3/Zero
ALPINE_VER="3.22.0"
TARBALL="alpine-rpi-${ALPINE_VER}-${ARCH}.tar.gz"
MIRROR="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER%.*}/releases/${ARCH}"

WORK=$(mktemp -d)
OVERLAY=$(mktemp -d)
trap 'rm -rf "$WORK" "$OVERLAY"' EXIT INT TERM

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

echo "→ verifying Alpine tarball"
curl -fsSL "$MIRROR/$TARBALL.sha256" | sha256sum -c -

echo "→ downloading Alpine rootfs"
curl -#SL "$MIRROR/$TARBALL" | tar -xz -C "$WORK"


# ── interactive prompts ────────────────────────────────────────────────
printf "FQDN                         : "; read HOST
printf "Root password                : "; read -s ROOTPW; echo
printf "Timezone (e.g. America/New_York): "; read TZ
printf "Keyboard layout (e.g. us)    : "; read KEYMAP
printf "SOPS age key                 : "; read AGEKEY
printf "SSH pubkey                   : "; read SSHKEY
printf "Add extra user? (y/N)        : "; read ADDUSR
if [ "$ADDUSR" = "y" ]; then
  printf "Username                     : "; read USER
  printf "Password                     : "; read -s USRPW; echo
fi
printf "Target block device (e.g. /dev/sdX): "; read DEV
[ -b "$DEV" ] || { echo "✗ $DEV is not a block device"; exit 1; }
printf "‼  ALL DATA on $DEV will be DESTROYED – type YES to continue: "
read CONFIRM
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