# UCKP (Cloud Key Gen2 Plus) — Hardware & Boot Reference

Model: **UCK-G2-PLUS** (`UCKP`), SoC **Qualcomm APQ8053** (= Snapdragon 625,
8× Cortex-A53, aarch64), 2 GB RAM.
All facts below were read live from the device at root over SSH (2026-10-01).

> Addresses/identifiers are placeholders here on purpose. Do not commit real
> LAN IPs, MACs, or serials.

---

## 1. Boot chain

Qualcomm MSM8953/APQ8053 boot flow (GPT on internal eMMC):

```
[ROM] -> sbl1 (p3) -> rpm (p5) / tz (p7) / devcfg (p9)
      -> aboot (p40, Android bootloader / LK)
      -> boot (p42, Android boot image) -> Linux kernel
      -> (or) recovery (p43)
```

- The **`boot` partition (p42) is a classic Android (v0) boot image**:
  magic `ANDROID!`, page size 4096.
  - `kernel_addr` 0x80008000, `ramdisk_addr` 0x81000000, `tags_addr` 0x80000100
  - kernel section = **`gzip(Image)` + appended DTB** (i.e. `Image.gz-dtb`):
    gzip stream, then an `0xd00dfeed` FDT blob immediately after.
  - ramdisk = standard `mkinitramfs` initramfs (Debian initramfs-tools).
- `recovery` (p43) is what the **"hold reset 30 s"** path boots (flashing mode).
- **No `QCDT` table** — the DTB is a single appended FDT.

### Why a foreign image (e.g. Raspberry Pi) can never boot this
- The P0 ROM only follows the Qualcomm chain above. There is **no code path**
  that looks for `bootcode.bin`/`start.elf`/`kernel8.img`.
- Different SoC, different DTB (`qcom,apq8053-mtp` vs `bcm2711`), different
  storage/console drivers. The Pi kernel would panic before userspace.

---

## 2. Storage map

### Internal eMMC `mmcblk0` — 29.1 GB, **47 partitions** (GPT)

| # | Name | Size | Purpose |
|---|---|---|---|
| 1 | `fsc` | 1 KB | file-system-context |
| 2 | `ssd` | 8 KB | secure data |
| 3 / 4 | `sbl1` / `sbl1bak` | 512 KB ea | Secondary Boot Loader |
| 5 / 6 | `rpm` / `rpmbak` | 512 KB ea | Resource Power Manager |
| 7 / 8 | `tz` / `tzbak` | 2 MB ea | TrustZone (secure OS) |
| 9 / 10 | `devcfg` / `devcfgbak` | 256 KB ea | device config |
| 11 | `dsp` | 16 MB | DSP firmware |
| 12 / 13 | `modemst1` / `modemst2` | 1.5 MB ea | modem NV |
| 14 | `DDR` | 32 KB | DDR training |
| 15 | `fsg` | 1.5 MB | modem FS |
| 16 | `sec` | 16 KB | security/fuse mirror |
| 17 | `splash` | 11 MB | **boot splash image** |
| 18 | `devinfo` | 1 MB | device state / lock flags |
| 19 | `misc` | 1 MB | bootloader control block |
| 20 | `keystore` | 512 KB | keystore |
| 21 | `config` | 32 KB | device config |
| 22 | `oem` | 256 MB | OEM blob |
| 23 | `limits` | 32 KB | thermal/power limits |
| 24 | `mota` | 512 KB | modem OTA |
| 25 | `dip` | 1 MB | debug interface |
| 26 | `mdtp` | 32 MB | modem/data transport |
| 27 | `syscfg` | 512 KB | system config |
| 28 | `mcfg` | 4 MB | modem config |
| 29 / 30 | `lksecapp` / `bak` | 128 KB ea | LK secure app |
| 31 / 32 | `cmnlib` / `bak` | 256 KB ea | common lib (crypto) |
| 33 / 34 | `cmnlib64` / `bak` | 256 KB ea | common lib 64-bit |
| 35 / 36 | `keymaster` / `bak` | 256 KB ea | keymaster |
| 37 | `apdp` | 256 KB | — |
| 38 | `msadp` | 256 KB | — |
| 39 | `dpo` | 8 KB | provision flag |
| 40 / 41 | `aboot` / `abootbak` | 1 MB ea | **Android bootloader (LK)** |
| 42 | **`boot`** | 64 MB | **kernel + initramfs (boot image)** |
| 43 | **`recovery`** | 64 MB | **recovery image** |
| 44 | **`rootfs`** | 2 GB (squashfs, ro) | read-only OS image |
| 45 | **`persist`** | 1 GB (ext4) | persistent data |
| 46 | **`overlay`** | 6 GB (ext4) | overlay upper (rw) |
| 47 | **`appdata`** | 19.1 GB (ext4) | app data |

### Root filesystem = **overlayfs**
```
lowerdir=/mnt/.rofs   (mmcblk0p44, squashfs, ro)
upperdir=/mnt/.rwfs/data (mmcblk0p46, ext4, rw)
workdir=/mnt/.rwfs/.workdir
```
⚠️ **This is the key structural fact**: `/` is a *merged overlay*. `/bin`,
`/sbin`, `/lib` exist in the **lower** layer, so they **cannot be `rename()`d**
across layers — it fails with `EXDEV` ("Invalid cross-device link").

### 1 TB SATA HDD `sda` — software RAID1 (mdadm)
| Part | Size | Role |
|---|---|---|
| sda1 | 512 MB | spare |
| sda2 | 2 GB | RAID1 member → **md0 (swap, 1.9 GB)** |
| sda3 | 1 GB | spare |
| sda5 | 923.5 GB | RAID1 member → **md3 (ext4, 923.4 GB)** |

Single-disk RAID1 (degraded mirror) — Ubiquiti stages Protect recordings here.

---

## 3. The on-device display

| | |
|---|---|
| Panel | **Visionox SP8110** |
| Driver | `fb_sp8110` → `/dev/fb0` |
| Bus | **SPI** (`/sys/class/graphics/fb0/device -> spi3.0`; DT `/soc/spi@78b7000/sp8110@0`, `visionox,sp8110`) |
| Geometry | **160 × 60 px, 16 bpp (RGB565)**, stride 320 B, **rotate=180** |
| Frame size | 160×60×2 = **19,200 bytes** |
| Console | none (serial `ttyHSL0`) |
| UI app | `/usr/bin/ck-ui` via `ck-ui.service` (Qt5 QGraphicsView, stripped) |

- `ck-ui` is a **compiled Qt app fed by gRPC** from UniFi core; it reads
  `/tmp/system.cfg`, logs to `/var/log/ui.log`, and shows IP/hostname/storage.
  It **owns `/dev/fb0` exclusively**.
- LED ring: `/usr/bin/uled-ctrl` (+ `uled-bootup-check.service`).
- Brightness: `LCM: brightness: 80`; Night Mode 1320→480.

**To put your own data on the panel:** `systemctl stop/disable ck-ui`, then
write RGB565 frames straight to `/dev/fb0` (rotated 180°). Reversible with
`systemctl start ck-ui`.

---

## 4. Repo/backup

- Full GPT + partition image backup routine is in `backup.sh`.
- Restore path: recovery mode + `reset2defaults` (Ubiquiti's own factory reset).
