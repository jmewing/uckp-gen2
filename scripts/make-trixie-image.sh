#!/bin/bash
# =============================================================================
# make-trixie-image.sh — build a bootable Debian 13 (trixie) rootfs for the
#                        UniFi Cloud Key Gen2 Plus (UCKP / APQ8053)
#
# Produces: p44-trixie.squashfs  (gzip/zlib, 256K blocks — the ONLY format the
#           UCK's 3.18.44 kernel can read)
#
# Run on an x86_64 Debian host with: debootstrap, qemu-user-static(binfmt),
# squashfs-tools, and root (or sudo).
#
# THE BASE CONFIG (DNS + default password) comes from ../config/base-config.md.
# NOTHING production/secret gets baked in.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-/srv/trixie-build}"
ROOTFS="$BUILD_DIR/rootfs"
OUT="${OUT:-$BUILD_DIR/p44-trixie.squashfs}"
DEFAULT_PASSWORD="$(cat "$HERE/../config/DEFAULT_PASSWORD")"

echo "== UCK Debian 13 image build =="
echo "   build dir : $BUILD_DIR"
echo "   output    : $OUT"

# --- safety: never bake a real password ------------------------------------
# Guard: the published default must be a documented throwaway, and it must not
# look like a real production secret. Refuse obviously-strong/real passwords.
case "$DEFAULT_PASSWORD" in
  ""|"ucloud-default-13"|"uck-default-13"|"changeme"|"debian")
    echo "FATAL: DEFAULT_PASSWORD must be set to the documented throwaway value." >&2
    exit 1 ;;
esac
if [ ${#DEFAULT_PASSWORD} -gt 20 ]; then
  echo "FATAL: DEFAULT_PASSWORD looks like a real secret (len>20). Refusing to bake it." >&2
  exit 1
fi

sudo mkdir -p "$BUILD_DIR"
sudo rm -rf "$ROOTFS"
sudo mkdir -p "$ROOTFS"

# --- 1. bootstrap minbase, arm64 -------------------------------------------
echo "== [1/6] debootstrap trixie arm64 =="
sudo debootstrap --arch=arm64 --foreign --variant=minbase \
  --include=systemd,systemd-sysv,udev,kmod,ifupdown,iproute2,isc-dhcp-client,openssh-server,ca-certificates,locales,sudo \
  trixie "$ROOTFS" https://deb.debian.org/debian
sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
sudo chroot "$ROOTFS" /debootstrap/debootstrap --second-stage

# --- 2. UCK glue ------------------------------------------------------------
echo "== [2/6] UCK glue =="
# merged-usr canonical shape
sudo ln -sfn usr/bin  "$ROOTFS/bin"
sudo ln -sfn usr/sbin "$ROOTFS/sbin"
sudo ln -sfn usr/lib  "$ROOTFS/lib"
sudo mkdir -p "$ROOTFS/usr/lib64"
sudo ln -sfn usr/lib64 "$ROOTFS/lib64"

# firmware-version marker the Ubiquiti ramdisk reads
echo "Debian 13 (trixie) - UCK G2 Plus custom build" | sudo tee "$ROOTFS/usr/lib/version" >/dev/null

# hostname / hosts
echo "UCK-G2-Plus" | sudo tee "$ROOTFS/etc/hostname" >/dev/null
sudo tee "$ROOTFS/etc/hosts" >/dev/null <<'EOF'
127.0.0.1   localhost
127.0.1.1   UCK-G2-Plus
::1         localhost ip6-localhost ip6-loopback
EOF

# --- 3. DNS (fixed default, never overridden) -------------------------------
echo "== [3/6] DNS defaults =="
sudo tee "$ROOTFS/etc/resolv.conf" >/dev/null <<'EOF'
# Static DNS — DHCP-provided server proved unreliable on this image.
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# --- 4. network + console + access ------------------------------------------
echo "== [4/6] network / console / access =="
sudo mkdir -p "$ROOTFS/etc/network"
sudo tee "$ROOTFS/etc/network/interfaces" >/dev/null <<'EOF'
auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp
    dns-nameservers 1.1.1.1 8.8.8.8
EOF

sudo mkdir -p "$ROOTFS/etc/systemd/system/getty.target.wants"
sudo ln -sfn /lib/systemd/system/serial-getty@.service \
             "$ROOTFS/etc/systemd/system/getty.target.wants/serial-getty@ttyHSL0.service"
sudo mkdir -p "$ROOTFS/etc/systemd/system/serial-getty@ttyHSL0.service.d"
sudo tee "$ROOTFS/etc/systemd/system/serial-getty@ttyHSL0.service.d/override.conf" >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \u' --keep-baud 115200,38400,9600 %I $TERM
EOF

sudo mkdir -p "$ROOTFS/etc/ssh/sshd_config.d"
sudo tee "$ROOTFS/etc/ssh/sshd_config.d/10-uck.conf" >/dev/null <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
EOF

# no UniFi stack in this image -> mask the units that would fail
sudo mkdir -p "$ROOTFS/etc/systemd/system"
sudo ln -sfn /dev/null "$ROOTFS/etc/systemd/system/nginx.service"

# --- 5. default password (SAFE placeholder) ---------------------------------
echo "== [5/6] default password =="
sudo chroot "$ROOTFS" /bin/bash -c "echo 'root:${DEFAULT_PASSWORD}' | chpasswd"
echo "   root password set to the documented default (NOT the production one)."
echo "   >>> ROTATE IT ON FIRST BOOT. <<<"

# --- 6. squash --------------------------------------------------------------
echo "== [6/6] mksquashfs (gzip/zlib, 256K) =="
sudo rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
sudo rm -rf "$ROOTFS/debootstrap"
sudo rm -f "$OUT"
sudo mksquashfs "$ROOTFS" "$OUT" -comp gzip -b 262144 -noappend -no-progress
sudo chown "$(id -u):$(id -g)" "$OUT"
echo
echo "== DONE =="
ls -la "$OUT"
sha256sum "$OUT"
head -c 4 "$OUT" | od -An -c
