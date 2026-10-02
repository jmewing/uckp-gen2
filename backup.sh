#!/bin/bash
# backup.sh — image the UCKP boot-critical partitions to the 1 TB volume.
# Reproducible safety net before any change. Run ON the device as root.
#
#   scp backup.sh root@<device>:/tmp/ && ssh root@<device> 'bash /tmp/backup.sh'
#
set -euo pipefail

# 1 TB RAID1 volume (ext4) mounted under /volume/<uuid>
VOL="$(df -h /volume/* 2>/dev/null | awk '/md3/{print $6}' | head -1)"
[ -n "$VOL" ] || { echo "1 TB volume not found"; exit 1; }

BK="$VOL/uckp-backup-$(date +%Y%m%d-%H%M)"
mkdir -p "$BK"
echo "==> backup dir: $BK"

# --- GPT layout (restorable with: sgdisk --load-backup=...) ---
sgdisk --backup="$BK/gpt-backup.bin" /dev/mmcblk0
sgdisk -p /dev/mmcblk0 > "$BK/gpt-print.txt"
echo "==> GPT saved"

# --- boot-critical partitions ---
# 42 boot, 43 recovery, 44 rootfs, 45 persist, 46 overlay
for spec in 42:boot 43:recovery 44:rootfs 45:persist 46:overlay; do
  n=${spec%%:*}; nm=${spec##*:}
  echo -n "==> imaging p$n ($nm) ... "
  dd if="/dev/mmcblk0p$n" of="$BK/p$n-$nm.img" bs=4M status=none
  sync
  echo "done ($(du -h "$BK/p$n-$nm.img" | cut -f1))"
done

# --- checksums ---
( cd "$BK" && sha256sum *.img *.bin > SHA256SUMS )
echo "==> checksums written"

# --- how to restore (documentation only) ---
cat > "$BK/RESTORE.md" <<'EOF'
# Restore

All commands as root, from the device's own shell (recovery or running OS).

## GPT
    sgdisk --load-backup=gpt-backup.bin /dev/mmcblk0

## Partitions
    dd if=p42-boot.img     of=/dev/mmcblk0p42 bs=4M conv=fsync
    dd if=p43-recovery.img of=/dev/mmcblk0p43 bs=4M conv=fsync
    dd if=p44-rootfs.img   of=/dev/mmcblk0p44 bs=4M conv=fsync
    dd if=p45-persist.img  of=/dev/mmcblk0p45 bs=4M conv=fsync
    dd if=p46-overlay.img  of=/dev/mmcblk0p46 bs=4M conv=fsync

## Verify
    sha256sum -c SHA256SUMS

## Last-resort factory reset (Ubiquiti)
Hold reset 30 s -> recovery mode, or from a running system:
    ubnt-systool reset2defaults
EOF

echo "==> done:"; ls -lah "$BK"
