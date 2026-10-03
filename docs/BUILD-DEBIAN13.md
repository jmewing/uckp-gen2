# Building and flashing Debian 13 (trixie) — VERIFIED WORKING METHOD

**Status: VERIFIED ON HARDWARE 2026-10-03.** Debian 13 (trixie) + systemd 257 boots,
survives a soft reboot, and survives a factory reset on the stock 3.18.44 vendor kernel.

The earlier conclusion in `DEBIAN13.md` that "systemd 257 needs kernel ≥4.15 and therefore
Debian 13 is impossible on 3.18" **was wrong** — corrected here. systemd 257's documented
minimum is **Linux ≥ 3.15** (`systemd/README`), so 3.18.44 is fine.

## The working recipe

### 1. Build the image (on an x86_64 Debian host)
```bash
sudo ./scripts/make-trixie-image.sh          # -> /srv/trixie-build/p44-trixie.squashfs
```
- `debootstrap --arch=arm64 --foreign trixie` + stage2 via `qemu-aarch64-static` binfmt.
- Glue applied: canonical merged-usr, `/usr/lib/version` marker, `ttyHSL0` serial getty,
  static DNS (`1.1.1.1`/`8.8.8.8`), throwaway root password, eth0 DHCP, nginx masked.
- `mksquashfs -comp gzip -b 262144` — **gzip/zlib only**; the kernel's
  `CONFIG_SQUASHFS_ZLIB=y` is the sole supported compressor.

### 2. Flash it (on the Cloud Key, from stock Debian 11)
```bash
scp p44-trixie.squashfs flash-trixie.sh root@<uck>:/root/
ssh root@<uck> 'bash /root/flash-trixie.sh'     # flashes p44, reboots
```

### 3. Verify after reboot
```bash
ssh root@<new-ip> 'bash /root/verify-trixie.sh'
```

## The trap (this is what broke attempt #1)

**Writing to p44 while it is still mounted as the live overlay lower corrupts the running
system.** Every binary segfaults and it will not boot. `flash-trixie.sh` unmounts
`/mnt/.rwfs` + `/mnt/.rofs` + `/persistent` + `/data` **before** writing p44.

Expect the shell to become unusable partway through: this is a merged-usr system, so
`/usr` comes from p44, and unmounting it detaches the running system's binaries. **The dd
writes complete first** — just reboot and the ramdisk rebuilds the overlay.

## Why not just dist-upgrade in place?

Ubiquiti's boot ramdisk calls `purify_userdev_data()` on every boot, which **deletes**
upgraded files from the writable overlay (`usr/lib/version`, `etc/ld.so.preload`,
`etc/ld.so.conf`, `etc/profile.d`, `etc/environment`, `etc/security`,
`etc/modules-load.d`, and every `etc/ld.so.conf.d/*.conf` mirrored in the rofs).
An in-place bookworm→trixie upgrade writes new copies of exactly those files into the
overlay, and the next boot deletes them. **Baking the finished rootfs into p44 avoids
this entirely** — the overlay is empty on first boot, so there is nothing to purge.

## Recovery

- Recovery-mode factory reset → stock Debian 11 (proven).
- SD card `/sdcard` can hold golden images + restore scripts (~2 min restore).
- **The DHCP address changes every boot** (.198 → .203 → .202 → .204 observed). Read it
  off the OLED display, or scan the LAN for MAC `d0:21:f9:6b:b0:d7`.

## Verified behavior matrix

| Test | Result |
|---|---|
| Boot Debian 13 / systemd 257 | ✅ |
| Soft reboot | ✅ (distinct boot IDs) |
| Factory reset (`/boot/reset2defaults` → ramdisk) | ✅ overlay reformatted, OS persists |
| Hardware recovery-mode reset | ⚠️ **not yet tested** — p43 still holds stock recovery; may reflash to stock |
| DNS + SSH | ✅ |
