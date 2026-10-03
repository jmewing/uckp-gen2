# UCK G2 Plus — Base Image Configuration (Debian 13 / trixie)

These are the baked-in defaults for every image we produce. **Do not deviate**
without updating this file.

## DNS (fixed default — do NOT let DHCP override)
```
/etc/resolv.conf:
  nameserver 1.1.1.1
  nameserver 8.8.8.8
```
Also mirrored as `dns-nameservers 1.1.1.1 8.8.8.8` in `/etc/network/interfaces`
so ifupdown re-applies it. Rationale: Debian 12/13 images had no working resolver
(the DHCP-provided server silently failed), which broke apt/curl on first boot.

## Default password — SAFE, NOT THE REAL ONE
```
root:<DEFAULT_PASSWORD>
```
`DEFAULT_PASSWORD` is a **placeholder filled at build time**. The build script MUST
refuse to bake a real/production password into a published image.
- The image we publish to the repo uses a documented, throwaway default password.
- Jeremy rotates it on first boot to the real one (kept out of the repo).
- **NEVER commit a real credential.** The first working image had a real password
  baked in; that image must not be published as-is. Rotate and use the throwaway default.

## Console / access
- serial console on `ttyHSL0` (115200) — `serial-getty@ttyHSL0` enabled
- `PermitRootLogin yes`, `PasswordAuthentication yes` (LAN appliance, SSH-only access)

## Network
- `allow-hotplug eth0` + DHCP. **NOTE: the DHCP address changes every boot** (.198 → .203 → .202 → .204).
  The OLED shows the current IP. Consider a static lease on the router.

## Merged-usr
- `/bin→usr/bin`, `/sbin→usr/sbin`, `/lib→usr/lib`, `/lib64→usr/lib64` (real dir).
  Required by trixie `base-files`.

## Filesystem
- root = overlayfs: lower = p44 (squashfs, gzip/zlib, 256K blocks), upper = p46 `/data`
- **squashfs MUST be gzip/zlib** — kernel has CONFIG_SQUASHFS_ZLIB=y; XZ/LZO/LZ4 are unset and will not boot.
