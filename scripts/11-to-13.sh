#!/bin/bash
# =============================================================================
# 11-to-13.sh — ONE-SHOT: stock Debian 11 Cloud Key -> Debian 13.
#
# Run this ON THE CLOUD KEY as root, with p44-trixie.squashfs + flash-trixie.sh
# already copied to /root (or fetch them first).
#
# Steps:  fetch/verify image -> flash -> reboot -> (verify on next boot)
# =============================================================================
set -uo pipefail
cd /root

echo "== UCK 11 -> 13 (one shot) =="

# 1. get the image if not present
if [ ! -f /root/p44-trixie.squashfs ]; then
  echo "!! /root/p44-trixie.squashfs missing."
  echo "   scp it from the build host, or run fetch-assets.sh on a host with the URL."
  exit 1
fi

# 2. verify
sha256sum /root/p44-trixie.squashfs

# 3. flash + reboot
bash /root/flash-trixie.sh
