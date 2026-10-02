# RECOVERY.md — Cloud Key Gen2 Plus: reset, recovery mode & reflash (plain language)

**Applies to:** UniFi Cloud Key Gen2 Plus (`UCK-G2-PLUS`), the spare unit used for the
Offgrid-Sentinel / Debian 13 repurpose experiments.

**When to use this:** the box won't boot, won't answer SSH/HTTP, hangs on the LCD, or
was deliberately broken during an experiment (e.g. the 2026-10-01 usrmerge lockout —
see `docs/DEBIAN13.md` §7).

---

## 0. Two facts people get wrong every time

1. **There is NO battery.** The blue "10-second countdown" on power loss is a
   **supercapacitor**. Once it drains, the box dies the instant power is removed.
   → **Do not wait for a graceful shutdown. Cut power and go straight to the cold
   sequence.** Nothing is lost by pulling the plug.

2. **The Reset button is a SOFT button.** It is read by the *firmware/OS*, so it only
   responds **while the box is running**. Pressing it on a dead/half-booted unit does
   nothing. This is why "I held reset and nothing happened."
   - *Quick press/release* = **restart**.
   - *Hold >5 s while running* = **factory reset** (needs a live system).
   - *Hold while applying power* = **recovery mode** (below). Different sequence.

---

## 1. Enter EMERGENCY RECOVERY MODE (works on a dead box)

Authoritative source: Ubiquiti Help — "UniFi Cloud Key Emergency Recovery UI"
(`help.ui.com/hc/en-us/articles/220334168`), for `UCK-G2` and `UCK-G2-PLUS`.

1. **Power OFF the system** — unplug PoE/Ethernet (and USB-C if used). It dies
   instantly; that's expected.
2. **Press and HOLD the Reset button.**
3. **While still holding**, apply power (plug PoE back in, or USB-C).
4. Keep holding **~10 seconds**, until the LED runs the recovery loop:
   **blue → off → white**, repeating at ~1 s intervals.
   - The QSG says the **LCD will read "RECOVERY MODE"**, but on a unit whose OS is
     broken the display app may not run — **trust the LED pattern instead.**
5. Open a browser to the box's IP.
   - IP normally comes from DHCP.
   - **Fallback IP: `192.168.1.30`** — but only works if no DHCP lease was assigned.
     Put a laptop on that subnet to reach it.
6. You land on the **Recovery Mode UI**: **reset**, **reboot**, **power off**, and
   **upload firmware (.bin)**.

---

## 2. Which recovery action to pick

| Situation | Action |
|---|---|
| Broken OS, but you want stock UniFi back | **Upload the model-correct firmware `.bin`**, then reboot. This rewrites the OS partitions. |
| Just want a clean slate | **Reset to factory defaults** from the recovery UI. |
| Want the device to stop booting the broken overlay | Either of the above. |

Recovery-mode reflash **does not touch the 1 TB SATA data volume** *by design*, but a
full factory reset / reformat **can**. See §4 before you wipe anything you care about.

---

## 3. Firmware `.bin` — get the RIGHT one

- Download page: `ui.com/download/unifi-cloud-key-gen2`
- **Model must be `UCK-G2-PLUS`.** Do **not** use:
  - a Gen2 **non-Plus** file,
  - a "UniFi OS **Server**" image,
  - an `UCK-G2`-only build.
- While upgrading the LED flashes **white**, then goes **steady white** when ready.

---

## 4. Power source (a real failure mode)

- **PoE (802.3af)** — most reliable. Use it if you can.
- **USB-C** — requires a **Quick Charge 2.0 / 3.0** adapter (**9 V / 2 A**).
  A plain 5 V phone charger will **not** power/boot it correctly — you'll chase
  phantom "won't boot" faults. This is a documented gotcha (Ubiquiti community:
  "bad USB-C power").

---

## 5. Backup safety (IMPORTANT for our unit)

The 2026-10-01 image backup lives **on the internal 1 TB SATA** at
`/volume/<uuid>/uckp-backup-20261001-2116/` (~9.2 GB: `gpt-print.txt`, `p42-boot.img`,
`p43-recovery.img`, `p44-rootfs`, p45 `persistent`, p46 `rwfs`, p47 `data`, sda/md
images).

- A **recovery-mode firmware reflash does not reformat the data volume.**
- A **factory reset / "reformat" can.**
- **Safest:** physically pull the **1 TB SATA drive** before wiping, copy the images
  off over USB-SATA on the Debian box, and `md5sum`-verify. Do this if we still want
  the dumped firmware/partition images.

---

## 6. After recovery — testing the corrected `/usr` merge

Only attempt the `/usr` merge on a **spare unit with a serial console**, using
**`merge-usr.sh`** (repo root). It exists specifically because the first attempt broke
`/lib` — see `docs/DEBIAN13.md` §7. Rules baked into the script:

- destructive step runs under a **statically-linked busybox**,
- refuses to proceed unless **`/usr/lib/ld-linux-aarch64.so.1` exists**,
- refuses to swap any of `/bin`,`/sbin`,`/lib` that **still holds files**,
- never deletes `/lib`'s top-level symlinks before the `/lib -> usr/lib` link is real.

Also note: **Debian 13 was never going to boot** on the stock vendor kernel
(`3.18.44-ui-qcom`, no **cgroup v2**). A kernel port (msm8953) is the real prerequisite
for the Debian 13 goal — the `/usr` merge is just one step of many.

---

## 7. Outcome log — 2026-10-01 22:17 CDT (this unit)

**Result: SUCCESS.** After the physical reset / recovery reflash the unit came back on
the LAN:

- IP **192.168.12.198**, MAC `d0:21:f9:6b:b0:d7`
- Ports open: **22, 80, 443, 8443** (full OS boot, not bare recovery)
- `/` → **UniFi OS**, HTTP/2 200 (nginx)
- `api/system`: `"deviceState":"setup"`, model `UCKP` ("UCK G2 Plus"),
  UniFi OS **`uckp-3.0.0`**, `cloudConnected:false`, `remoteAccessEnabled:false`,
  `hasInternet:true`
- So: **factory-fresh UniFi OS 3.0.0, awaiting setup** — the broken overlay is gone.

**Note on the 1 TB backup volume:** the reset path was *not* verified to preserve
`/volume/<uuid>/uckp-backup-20261001-2116/`. Treat those images as **suspect until we
can SSH in and confirm** (needs a configured login). If we still want the dumped
firmware/partition images, pull the SATA drive and copy them off before reformatting.

**Lesson confirmed:** the `usrmerge` lockout is exactly the kind of failure that needs
a *physical* path back. `merge-usr.sh` exists so the next attempt doesn't need one.
