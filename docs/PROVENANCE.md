# Provenance

## Kernel source (Ubiquiti GPL)

- **Origin:** Ubiquiti's official GPL source release **`UCKP-2.5.11-GPL.tar.gz`**
  (UniFi Cloud Key Plus). Member used:
  `UCKP-2.5.11-GPL/linux-qcom-apq8053-3.18.44-ui-qcom.tar`
  — kernel tar sha256 `d1d733355c29919cc3d2ce461bcf2de8e5e4485b3c2dc6ceef59d5cef58e3663` (1,910,497,280 bytes).
- **Browsable mirror we obtained it from:** `https://github.com/hutchx86/ckg2plus-kernel-src`
  — **credit: hutchx86**, who extracted and published the tree (unmodified except for
  removed build artifacts).
- **Upstream authors:** Ubiquiti Networks, Qualcomm, and the Linux kernel community.
  License: **GPL-2.0**.
- Our board file: `arch/arm64/boot/dts/qcom/apq8053-ck-plus.dts` →
  `apq8053.dtsi` + `msm8953-ck-plus.dtsi`.

**We vendor a copy** of this tree in our own repo so it survives if the third-party
mirror disappears. Credit remains with the original authors; the mirror is acknowledged.

## Firmware images

- Stock UCKP firmware: served publicly by Ubiquiti (`dl.ui.com` / `fw-update.ui.com`).
  Recovery/bootstrap image: `UCKP.apq8053.v0.8.6.…bin`.
- Our Debian 13 image is built from scratch (debootstrap) — see `scripts/make-trixie-image.sh`.

## Hardware

- UniFi Cloud Key Gen2 Plus, model `UCKP`, Qualcomm APQ8053 / msm8953, eMMC `mmcblk0`.
- Partitions of interest: p42 boot, p43 recovery, p44 rootfs (squashfs), p45 persist,
  p46 overlay, p47 appdata.
