# UCKP Gen2 Plus — repurpose notes

Working notes, scripts, and findings for repurposing a **UniFi Cloud Key Gen2
Plus** (UCK-G2-PLUS / `UCKP`) into a general-purpose server.

Hardware: **Qualcomm APQ8053** (Snapdragon 625, aarch64), 1 TB 2.5" HDD,
internal eMMC, PoE-powered, small **160×60 SPI OLED**.

## Start here

1. **Recovery / flashing mode** — hold reset for **30 s**, then flash firmware
   **v0.8.6** (`UCKP.apq8053.v0.8.6.8cf5792.181017.0942.bin` from `dl.ubnt.com`),
   which leaves more free space in the `rootfs`/`overlay` partitions than the
   newer UniFi OS images:
   `https://dl.ubnt.com/unifi/cloudkey/firmware/UCKP/UCKP.apq8053.v0.8.6.8cf5792.181017.0942.bin`
2. Factory-reset, reboot.
3. `ssh ubnt@<device>` (default `ubnt/ubnt`).
4. `wget <raw-url>/reinstall.sh && bash reinstall.sh`
   — the script **reboots after each stage**; just run it again and it continues.

## Scripts

| File | Purpose |
|---|---|
| `reinstall.sh` | staged userland upgrader (Debian stretch → Ubuntu focal). Resumable. |
| `recon.sh` | dump all hardware/boot/display facts (read-only). |
| `backup.sh` | image the boot-critical partitions to the 1 TB volume. |
| `fbwrite.sh` | draw text/status onto the 160×60 OLED (takes over `/dev/fb0`). |

## Documentation

- [`docs/HARDWARE.md`](docs/HARDWARE.md) — full partition map, boot chain, display wiring.
- [`docs/DEBIAN13.md`](docs/DEBIAN13.md) — why Debian 12/13 is blocked, and the paths forward.

## TL;DR of what we learned (2026-10-01)

- The **`boot` partition is an Android v0 boot image**: `gzip(Image)` + appended
  DTB. The kernel is **3.18.44-ui-qcom**; the initramfs (inside that image) holds
  the vendor modules and Ubiquiti's overlay-mount scripts.
- Root is an **overlayfs** (`rootfs` squashfs ro + `overlay` ext4 rw). That's why
  `usrmerge` **fails** with `EXDEV` — you cannot rename a lower-layer dir.
- **Debian 12/13 needs merged-/usr** (the same wall that killed the jammy
  attempt) and prefers **cgroup v2** (the 3.18 kernel has v1 only).
- A Raspberry Pi / any foreign image **cannot boot** this — wrong boot chain, SoC,
  DTB, drivers.

## Safety

- `backup.sh` first. Ubiquiti's `reset2defaults` (or recovery mode) is always a
  fallback — it rewrites the eMMC from the firmware image.
- `reinstall.sh`'s `Ctrl-C` trap runs `ubnt-systool reset2defaults`.
