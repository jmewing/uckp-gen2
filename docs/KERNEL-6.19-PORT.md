# UCK G2 Plus — Mainline Linux 6.19 Kernel Port: Status & Findings

> Status: **blocked on USB3 SuperSpeed PHY** (see "Root cause" below). Kernel builds and
> boots to userspace; the box has no network because the internal USB Ethernet is
> SuperSpeed-only. This is a write-up of verified findings, the build/flash recipe, and the
> exact remaining work — so anyone with a UCK G2 Plus can reproduce and finish the port.

---

## 1. Device facts

| Item | Value |
|---|---|
| Model | UniFi Cloud Key Gen2 Plus (`UCKP`), hostname `UCK-G2-Plus` |
| SoC | Qualcomm **APQ8053** / MSM8953 (Snapdragon 625) |
| SoC ID (socinfo) | `id=304` (0x130), `raw_id=102`, `raw_ver=1`, `hw_plat=250` (0xfa) |
| Bootloader | Qualcomm LK (`aboot`, p40/p41) — **secure boot OFF**, boots unsigned images |
| Stock kernel | `3.18.44-ui-qcom` (Ubiquiti vendor GPL) |
| Boot image format | `ANDROID!` header on p42; `mkbootimg` params below |

### Partition layout (eMMC, `/dev/mmcblk0`)

| Part | Label | Contents |
|---|---|---|
| p40 | aboot | bootloader |
| p41 | abootbak | bootloader backup |
| p42 | boot | kernel + ramdisk (64 MiB) |
| p43 | recovery | recovery mode image |
| p44 | rootfs | squashfs (Debian trixie lower) |
| p45 | persistent | raw |
| p46 | rwfs/overlay | ext4 overlay upper |
| p47 | appdata | ext4 |
| `mmcblk1p1` | SD card | `/srv` (117G) — capture + rollback images live here |

### Boot chain (verified)

```
aboot (p40) ── boots p42 (ANDROID! header, kernel+ramdisk) ── ramdisk /init
  ├─ mounts p44 (squashfs) + p46 (ext4) → overlayfs
  └─ execs systemd (Debian 13 trixie)
```

`aboot` selects the DTB from `qcom,msm-id`/`qcom,board-id` (it matches appended DTBs; a
wrong id produces `"Couldn't find the suitable DTB!"`).

---

## 2. Root cause of "the box won't come up" — two bugs, both verified

**The 6.19 kernel has been booting to userspace successfully the whole time.** A real
6.19 marker on the SD card (`6.19-boot-markers.log`, kernel `6.19.0-uck`, monotonic
~14.8s) proves it reaches userspace. It was *not* hanging. It looks "dead" for two reasons:

### Bug 1 — console label mismatch (visibility)

- The stock aboot passes `console=ttyHSL0,115200n8`.
- Mainline `msm_serial` registers the console as **`ttyMSM`** (not `ttyHSL0`).
  `drivers/tty/serial/msm_serial.c`: `.dev_name = "ttyMSM"`, `.name = "ttyMSM"`.
- Mainline has **zero** `ttyHSL` support, so `console=` never binds → **every boot was
  silent**, even when the kernel was booting fine.

**Fix (applied in v12):** `console=ttyMSM0,115200n8` in the mkbootimg cmdline. Also
`earlycon` (`qcom,msm-uartdm`) is available if pre-console output is wanted.

### Bug 2 — no USB3 SuperSpeed PHY in mainline msm8953 (the real blocker)

The UCK G2 Plus has **no on-SoC Ethernet**. LAN is an **ASIX AX88179** (`0b95:1790`) USB3
NIC behind a **TI USB3 hub** (`0451:8440`) on the **SuperSpeed (3.0) root hub**; the SATA
bridge (`174c:1153`) is also on the SS hub. Live 3.18 topology:

```
eth0 → 7000000.ssusb/7000000.dwc3/xhci-hcd.0.auto/usb2/2-1/2-1.1 → AX88179
```

Mainline `msm8953.dtsi` only wires the **HS (UTMI) PHY** (`qcom,msm8953-qusb2-phy`) and
caps `maximum-speed = "high-speed"` on the dwc3. There is **no QMP SuperSpeed PHY node
(`ssphy@78000`) anywhere in mainline msm8953**, and the QMP driver has no msm8953 entry.

The vendor DTS (on disk at `kernel-port/vendor-dts/`) uses a QMP SuperSpeed PHY:

```dts
dwc3: dwc3@7000000 {
    compatible = "snps,dwc3";
    usb-phy = <&qusb_phy>, <&ssphy>;      /* HS *and* SS PHY */
    ...
};
ssphy: ssphy@78000 {
    compatible = "qcom,usb-ssphy-qmp";    /* QMP v3 family, same as msm8996 */
    ...
};
```

**Net:** no SS PHY → TI hub never enumerates → no AX88179 → no `eth0` → no network → the
`uck-bootcheck.service` (which runs `After=multi-user.target network.target`) never fires →
no capture, no auto-rollback, box sits dark.

---

## 3. What's already fixed / verified

- ✅ `qcom,msm-id = <304 0>` (was `293` — that was the v2 no-boot fix; hardware reports 304)
- ✅ `qcom,board-id = <250 0>` (correct)
- ✅ DTB `model` string matches the vendor string (the ramdisk keys off `model`)
- ✅ `ramoops@92000000` for pstore crash visibility
- ✅ eMMC (`sdhc_1`) + SD (`sdhc_2`) + PMIC regulators + power/reset keys in DTS
- ✅ All USB3 PHY clocks exist in `gcc-msm8953` (`GCC_USB3_AUX_CLK`, `GCC_USB3_PIPE_CLK`,
  `GCC_USB_SS_REF_CLK`, `GCC_USB_PHY_CFG_AHB_CLK`, `GCC_QUSB_REF_CLK`, resets `GCC_USB3_PHY_BCR`/
  `GCC_USB3PHY_PHY_BCR`, gdsc `USB30_GDSC`)
- ✅ QMP USB3 PHY driver (`phy-qcom-qmp-usb.c`) has `qcom,msm8996-qmp-usb3-phy` (QMP v3,
  same family as msm8953) — the reference for the port
- ✅ `console=ttyMSM0` fix (v12)
- ✅ initramfs dmesg dump to the SD card (capture path that ends blind debugging)

---

## 4. The remaining work — port the SuperSpeed PHY (one DTS + maybe a driver tweak)

1. **Add an `ssphy` node** to `msm8953-ubiquiti-uck.dts`, modeled on the vendor
   `ssphy@78000` (`qcom,usb-ssphy-qmp`, reg `0x78000`), but using the **mainline**
   compatible `qcom,msm8996-qmp-usb3-phy` (QMP v3) — reference the msm8996 node in
   `msm8996.dtsi` for the mainline binding shape.
2. **Wire it into dwc3:** `phys = <&hsusb_phy>, <&ssphy>; phy-names = "usb2-phy", "usb3-phy";`
3. **Remove** `maximum-speed = "high-speed"` from `&usb3_dwc3`.
4. Keep `dr_mode = "host"` and drop `usb-role-switch` (already done — avoids the
   default-PERIPHERAL trap).
5. Confirm the AX88179 enumerates on the 3.0 root hub (`/sys/class/net/eth0` present).

The gcc clocks/resets/gdsc for the QMP SS PHY are already present in mainline msm8953
(verified §3), so this is primarily a DTS wiring task, not a clock driver port.

---

## 5. Build recipe (reproducible, from scratch)

```bash
# 1. kernel tree
git clone --depth 1 https://github.com/msm8953-mainline/linux.git
cd linux
# checkout the 6.19 head used: 05f7e89ab973

# 2. add the board DTS + qcom Makefile entry (files in kernel-port/)
#    arch/arm64/boot/dts/qcom/msm8953-ubiquiti-uck.dts
#    build-assets/qcom-dts-Makefile

# 3. config (defconfig + UCK options, built-in for the stock ramdisk)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
# enable: BLK_DEV_LOOP SQUASHFS SQUASHFS_ZLIB EXT4_FS OVERLAY_FS DEVTMPFS
#         USB_DWC3 USB_DWC3_QCOM USB_XHCI_PLATFORM USB_NET_AX88179_178A USB_STORAGE
#         MMC_SDHCI_MSM SERIAL_MSM SERIAL_MSM_CONSOLE PSTORE_RAM PSTORE_CONSOLE
# (see kernel-port/config-6.19-uck for the full working config)

# 4. build
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image dtbs

# 5. assemble the boot image (ANDROID! format for aboot)
gzip -9 -c arch/arm64/boot/Image > Image.gz
cat Image.gz arch/arm64/boot/dts/qcom/msm8953-ubiquiti-uck.dtb > kernel-with-dtb
mkbootimg --kernel kernel-with-dtb --ramdisk ramdisk.img \
  --base 0x80000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00f00000 --tags_offset 0x00000100 --pagesize 4096 \
  --cmdline "console=ttyMSM0,115200n8 net.ifnames=0 quiet" \
  --output uck-6.19-boot.img
```

The `ramdisk.img` is the **stock Ubiquiti ramdisk** (extracted from p42, optionally
patched to add the initramfs dmesg dump).

---

## 6. Flash + recovery (the safe loop)

**Flash (on-device):**
```bash
dd if=uck-6.19-boot.img of=/dev/mmcblk0p42 bs=1M conv=fsync && sync && reboot -f
```

**Recovery mode** (always available; requires physical access):
1. Hold **Reset** while applying power ~10s → LED blue→off→white blinking ~1Hz.
2. Device lands at its **DHCP-assigned recovery address** (LED blue→off→white).
   `telnet <recovery-ip>`, login `root`/`ubnt`.
3. Mount the SD card: `mount /dev/mmcblk1p1 /mnt`
4. **Rollback** to stock p42: `dd if=/mnt/p42-boot-CURRENT.img of=/dev/mmcblk0p42 bs=1M conv=fsync && sync && reboot -f`

> **Note:** recovery uses DHCP (one address); every boot after recovery gets a fresh
> DHCP address — the running address changes per boot.

---

## 7. Bootchain images included in this repo

Small, git-friendly bootloader images (with SHA256) are in `bootchain/`:

| File | Partition | Size | SHA256 |
|---|---|---|---|
| p40-aboot.img | aboot | 1 MiB | `29576e57…e4934d690b4` |
| p41-abootbak.img | abootbak | 1 MiB | `29576e57…e4934d690b4` |
| p18-devinfo.img | devinfo | 1 MiB | `19a69cce…d125247990caa3` |
| p19-misc.img | misc | 1 MiB | `30e14955…b8af909fcb58` |

Full `SHA256SUMS` is in `bootchain/`. The larger images (p42 boot 64 MiB, p43 recovery
64 MiB) are excluded from git (see `.gitignore`) — their hashes are recorded below and they
are available as release assets / SD-card backups.

```
9ce8eaf97ca006eb63b29784e38beffeed02fa17dfd33145b0a1fc64f39e5638  p42-boot.img   (stock 3.18 boot)
664b118b6e8fab45484113eb45d16cf0240f20552bbb941528d01ab0444974e4  p43-recovery.img
```

---

## 8. Build artifacts

- Kernel tree: `msm8953-mainline/linux` @ `05f7e89ab973` "Linux 6.19"
- Image: `arch/arm64/boot/Image` 41,216,512 B
- DTB: `msm8953-ubiquiti-uck.dtb` 43,026 B, model "Ubiquiti Networks, Inc. APQ8053 CloudKey Plus"
- Boot image: `uck-6.19-boot.img` 22,073,344 B (`ANDROID!` header)

## 9. Key files in this repo

```
kernel-port/
  msm8953-ubiquiti-uck.dts     # the board DTS (current, v12-era)
  config-6.19-uck              # full 6.19 kernel config
  build-mainline.sh            # build recipe
  vendor-dts/                  # Ubiquiti vendor DTS reference (for the SS PHY port)
  qcom-dts-Makefile            # Makefile entry for the board DTB
bootchain/                     # stock bootloader images + SHA256SUMS
docs/KERNEL-6.19-PORT.md       # this document
```
