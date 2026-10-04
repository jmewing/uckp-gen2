# uckp-gen2 — UniFi Cloud Key Gen2 Plus: Debian 13 (trixie) on the stock kernel

Turn a UniFi Cloud Key Gen2 Plus (`UCK G2 Plus`, model `UCKP`, Qualcomm **APQ8053**
/ Snapdragon 625) from stock Debian 11 into **Debian 13 (trixie) + systemd 257**,
running on the **unmodified Ubiquiti 3.18.44 vendor kernel**.

**Verified 2026-10-03 on real hardware:**
- boots Debian 13 / systemd 257 ✅
- survives a soft reboot ✅ (distinct boot IDs)
- survives a factory reset ✅ (overlay reformatted; OS persists)
- DNS + SSH working ✅

## TL;DR

```bash
# ON A BUILD HOST (x86_64 Debian, root/sudo):
scripts/make-trixie-image.sh          # -> p44-trixie.squashfs (~140 MB)

# COPY TO THE CLOUD KEY (it must be on stock Debian 11):
scp p44-trixie.squashfs root@<uck>:/root/
scp scripts/flash-trixie.sh root@<uck>:/root/

# ON THE CLOUD KEY:
ssh root@<uck> 'bash /root/flash-trixie.sh'     # flashes p44 + reboots
# ... wait for it to come back, find the new IP on the OLED ...
ssh root@<new-ip> 'bash /root/verify-trixie.sh' # or copy it over
```

## Why this works (and the one trap)

The UCK boots: **p42 ramdisk** → mounts **p44** (squashfs, read-only rootfs lower) +
**p46** (ext4, overlay upper) → assembles an **overlayfs** → execs systemd.

- **The kernel is NOT the blocker.** systemd 257's minimum is Linux ≥ 3.15; the UCK
  ships 3.18.44. Baked-in drivers cover eMMC/overlay/USB, so it boots fine.
- **Do NOT dist-upgrade in place.** Ubiquiti's ramdisk `purify_userdev_data()` deletes
  upgraded files (`/etc/ld.so.conf.d/*`, `/etc/modules-load.d/*`, `/usr/lib/version`, …)
  from the writable overlay on every boot. Bake the finished rootfs into p44 instead.
- **⚠️ THE TRAP:** writing to **p44 while it is still mounted** as the live overlay lower
  corrupts the running system — binaries segfault and it will not boot. `flash-trixie.sh`
  tears the overlay down **first**. Expect the shell to break partway (merged-usr `/usr`
  comes from p44); the writes finish before it does. Then reboot.

## Images must be gzip/zlib squashfs

The 3.18.44 kernel has `CONFIG_SQUASHFS_ZLIB=y` only. **XZ/LZO/LZ4 will not boot.**

## Recovery (always available)

- **Factory reset** (recovery mode) → back to stock Debian 11.
- **SD card** (`/sdcard`) can hold golden images + `FLASH-DEBIAN12.sh` (~2 min restore).
- The DHCP address **changes every boot** — read it off the OLED display.

## Contents

```
scripts/
  make-trixie-image.sh   build the Debian 13 squashfs (debootstrap + qemu + mksquashfs)
  fetch-assets.sh        download the image + stock boot images + Ubiquiti stock fw
  flash-trixie.sh        ON-DEVICE: safely flash p44 + reboot
  11-to-13.sh            ON-DEVICE: one-shot wrapper
  verify-trixie.sh       ON-DEVICE: post-boot health check
config/
  base-config.md         the base image config (DNS, password policy, merged-usr, …)
  DEFAULT_PASSWORD       safe throwaway default (placeholdered at build time)
docs/
  PROVENANCE.md          where the kernel source came from + credit
```

## Kernel source credit

Ubiquiti's official GPL release `UCKP-2.5.11-GPL.tar.gz` → `linux-qcom-apq8053-3.18.44-ui-qcom`
(GPL-2.0). Browsable mirror: `github.com/hutchx86/ckg2plus-kernel-src` — **credit to hutchx86**
for extracting/publishing it; the source itself is Ubiquiti's / Qualcomm's / the Linux
kernel's. See `docs/PROVENANCE.md`. A vendored copy is kept in this repo so it survives if
the mirror disappears.

## Security

**Never commit a real password.** `config/DEFAULT_PASSWORD` is a throwaway; the build
script refuses to bake the production password. Rotate on first boot.
