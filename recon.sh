#!/bin/bash
# recon.sh — capture UCKP hardware/boot facts, reproducibly. Run ON device as root.
#
#   scp recon.sh root@<device>:/tmp/ && ssh root@<device> 'bash /tmp/recon.sh'
#
# Output is grouped and safe to paste into docs.
set -uo pipefail

hr(){ printf '\n===== %s =====\n' "$1"; }

hr "OS / kernel"
uname -a
cat /etc/os-release | head -4
echo "systemd: $(systemctl --version 2>/dev/null | head -1)"
echo "glibc:   $(ldd --version 2>/dev/null | head -1)"
echo "merged-/usr:  $( [ -L /bin ] && echo YES || echo NO )"

hr "Storage: eMMC partitions (GPT)"
parted -s /dev/mmcblk0 print 2>/dev/null || sgdisk -p /dev/mmcblk0

hr "Mounts / overlay"
mount | egrep "overlay|rofs|rwfs|appdata|persist"

hr "Block devices"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null

hr "1 TB RAID"
cat /proc/mdstat 2>/dev/null

hr "Boot image (p42) header"
python3 - <<'PY' 2>/dev/null
import struct,zlib
d=open('/dev/mmcblk0p42','rb').read(64*1024*1024)
def u32(o): return struct.unpack('<I', d[o:o+4])[0]
print("magic:", d[:8])
ks,rs,ps = u32(8),u32(16),u32(36)
print("kernel_size=%d ramdisk_size=%d page=%d"%(ks,rs,ps))
print("kernel_addr=%#x ramdisk_addr=%#x tags=%#x"%(u32(12),u32(20),u32(32)))
ko=ps; ksec=d[ko:ko+ks]
g=zlib.decompressobj(16+zlib.MAX_WBITS); g.decompress(ksec)
consumed=len(ksec)-len(g.unused_data)
print("gzip=%d  appended-dtb=%d bytes  dtb-magic@%d"%(consumed,len(ksec)-consumed,ksec.find(b'\xd0\x0d\xfe\xed')))
PY

hr "Display / framebuffer"
for f in name virtual_size bits_per_pixel stride rotate; do
  printf "fb0/%-16s = " "$f"; cat /sys/class/graphics/fb0/$f 2>/dev/null; echo
done
readlink /sys/class/graphics/fb0/device 2>/dev/null
cat /sys/class/graphics/fb0/device/uevent 2>/dev/null | egrep "DRIVER|OF_NAME|MODALIAS"

hr "On-screen UI service"
systemctl status ck-ui.service --no-pager 2>/dev/null | head -6
ls -la /usr/bin/ck-ui /usr/bin/uled-ctrl 2>/dev/null

hr "Device tree (live)"
ls -la /sys/firmware/fdt 2>/dev/null
cat /sys/firmware/devicetree/base/model 2>/dev/null; echo
cat /sys/firmware/devicetree/base/compatible 2>/dev/null | tr '\0' ' '; echo

hr "cgroup"
mount | grep cgroup2 || echo "cgroup2 NOT mounted (v1 only)"
