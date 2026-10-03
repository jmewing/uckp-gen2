#!/bin/bash
# =============================================================================
# flash-trixie.sh — take a UniFi Cloud Key Gen2 Plus from stock Debian 11
#                   to Debian 13 (trixie) in one shot, reproducibly.
#
# RUN THIS ON THE CLOUD KEY ITSELF (as root), from a directory holding the image.
#
#   scp p44-trixie.squashfs root@<uck>:/root/
#   scp flash-trixie.sh     root@<uck>:/root/
#   ssh root@<uck>
#   bash /root/flash-trixie.sh
#
# WHY THIS WORKS / WHAT IT DOES
#   The UCK boots: p42 ramdisk -> mounts p44 (squashfs, read-only rootfs lower)
#   + p46 (ext4, overlay upper) -> assembles overlayfs -> runs systemd.
#
#   THE TRAP (learned the hard way 2026-10-03, attempt #1):
#     Writing to p44 while it is still mounted as the live overlay lower
#     CORRUPTS the running system — every binary segfaults and it will not boot.
#     This script tears the overlay down FIRST, then writes p44.
#
#   Expect the shell to become unusable partway through (unmounting p44 detaches
#   /usr, because this is a merged-usr system). That is NORMAL — the writes
#   complete before the shell breaks. Then reboot.
#
#   Kernel is NOT touched: 3.18.44 handles systemd 257 fine (min is 3.15).
# =============================================================================
set -uo pipefail   # NOT -e: the shell will start failing on purpose mid-run

IMG="${IMG:-/root/p44-trixie.squashfs}"
P44=/dev/mmcblk0p44
P46=/dev/mmcblk0p46
EXPECTED_SHA="${EXPECTED_SHA:-}"   # optional: verify before writing

echo "== UCK: stock Debian 11 -> Debian 13 =="

if [ ! -f "$IMG" ]; then echo "FATAL: image not found: $IMG"; exit 1; fi

if [ -n "$EXPECTED_SHA" ]; then
  got=$(sha256sum "$IMG" | awk '{print $1}')
  [ "$got" = "$EXPECTED_SHA" ] || { echo "FATAL: image sha mismatch ($got)"; exit 1; }
  echo "   image sha OK"
fi

echo "-- recording the current p44 (stock D11) to the SD card first, if present --"
if [ -b /dev/mmcblk1p1 ] && [ -d /sdcard ]; then
  if [ ! -f /sdcard/p44-stock-d11-$(date +%Y%m%d).img ]; then
    dd if="$P44" of=/sdcard/p44-stock-d11-$(date +%Y%m%d).img bs=1M conv=fsync status=none \
      && echo "   saved /sdcard/p44-stock-d11-$(date +%Y%m%d).img" || echo "   (backup skipped)"
  fi
fi

cd /

echo "== STEP 1: tear down the overlay (p44/p46/p45 must NOT be in use) =="
for m in /mnt/.rwfs /mnt/.rofs /persistent /data; do
  mountpoint -q "$m" 2>/dev/null && { echo "   umount $m"; umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; }
done
echo "   (binaries may start failing from here — expected, keep going)"

echo "== STEP 2: write the Debian 13 image into p44 =="
dd if=/dev/zero of="$P44" bs=1M count=16 conv=fsync 2>/dev/null
dd if="$IMG" of="$P44" bs=1M conv=fsync 2>/dev/null
echo "   written"

echo "== STEP 3: clear the overlay upper (p46 /data + /.workdir) =="
mkdir -p /mnt/.rwfs 2>/dev/null
mount "$P46" /mnt/.rwfs 2>/dev/null
rm -rf /mnt/.rwfs/data /mnt/.rwfs/.workdir 2>/dev/null
mkdir -p /mnt/.rwfs/data /mnt/.rwfs/.workdir 2>/dev/null
sync 2>/dev/null

echo "== STEP 4: reboot into Debian 13 =="
echo "   p44 magic: $(dd if=$P44 bs=4 count=1 2>/dev/null | od -An -c 2>/dev/null)"
sync 2>/dev/null
(sleep 2; reboot -f) >/dev/null 2>&1 &
echo "   rebooting..."
