# bootstrap.sh
#!/usr/bin/env sh
set -eu

ARCH="aarch64"                               # change for armv7 if needed
ALPINE_VER="3.22.0"
TARBALL="alpine-rpi-${ALPINE_VER}-${ARCH}.tar.gz"
MIRROR="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER%.*}/releases/${ARCH}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# === prompt ===
printf "Target block device (e.g. /dev/sdX): "; read DEV
[ -b "$DEV" ] || { echo "No such block device"; exit 1; }

printf "Cluster hostname (FQDN): "; read FQDN
printf "Root password: "; read -s ROOTPW; echo
printf "SSH pubkey: "; read SSHKEY
printf "Age key for SOPS: "; read AGEKEY

# === fetch image ===
echo "→ downloading Alpine rootfs"
curl -#SL "$MIRROR/$TARBALL" | tar -xz -C "$WORK"

# === configure rootfs ===
ROOT="$WORK"
echo "$FQDN"           > "$ROOT/etc/hostname"
echo "$SSHKEY"         > "$ROOT/root/.ssh/authorized_keys"
chmod 600 "$ROOT/root/.ssh/authorized_keys"

echo "$AGEKEY"         > "$ROOT/root/.sops/age.key"
chmod 600 "$ROOT/root/.sops/age.key"

echo "root:$ROOTPW" | chroot "$ROOT" chpasswd

chroot "$ROOT" apk add --no-cache openssh chrony k0s kubelet fluxcd sops age
chroot "$ROOT" rc-update add sshd  default
chroot "$ROOT" rc-update add chronyd default
chroot "$ROOT" rc-update add k0scontroller default

cat > "$ROOT/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# === write to disk ===
echo "→ wiping $DEV & writing image"
sgdisk --zap-all "$DEV"
dd if=/dev/zero of="$DEV" bs=1M count=10 status=progress
parted -s "$DEV" mklabel gpt mkpart primary ext4 1MiB 100%
mkfs.ext4 -F "${DEV}1"

MNT=$(mktemp -d)
mount "${DEV}1" "$MNT"
cp -a "$ROOT"/* "$MNT"
umount "$MNT"
sync

echo "✓ bootstrap complete – insert card and boot Pi"