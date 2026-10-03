#!/bin/bash
# verify-trixie.sh — run AFTER the reboot to confirm Debian 13 came up clean.
set -uo pipefail
echo "== UCK Debian 13 verification =="
echo "os-release : $(grep PRETTY_NAME /etc/os-release 2>/dev/null)"
echo "kernel     : $(uname -r)"
echo "systemd    : $(systemctl --version 2>/dev/null | head -1)"
echo "pid1       : $(cat /proc/1/comm 2>/dev/null)"
echo "state      : $(systemctl is-system-running 2>/dev/null)"
echo "failed     : $(systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l) units"
echo "boot_id    : $(cat /proc/sys/kernel/random/boot_id)"
echo "network    : $(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}')"
echo "dns        : $(getent hosts deb.debian.org >/dev/null 2>&1 && echo OK || echo FAIL)"
echo
echo "--- root should be overlayfs on p44(Trixie)+p46 ---"
grep -E "overlayfs-root" /proc/mounts 2>/dev/null | head -1
