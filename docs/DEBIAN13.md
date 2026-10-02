# Upgrading UCKP to Debian 13 (trixie) — findings

Date: 2026-10-01. Tested live on a factory-reset UCK-G2-PLUS.

## Executive summary

Going to Debian 12/13 is **not** a `sources.list` edit like the original
`reinstall.sh` ladder. There are **two independent blockers**, and one of them is
**structural to the device** (the overlay filesystem):

| # | Blocker | Severity | Fixable? |
|---|---|---|---|
| 1 | **merged-/usr required** by Debian 12+; the device is not merged | **hard** | Only by fixing `usrmerge` on an overlay root (see §2) |
| 2 | **cgroup v1 only** — no cgroup v2 | medium | Kernel 3.18 has no cgroup2; systemd 252+ runs hybrid/deprecated |
| 3 | Kernel **3.18.44** | *not* a blocker | systemd needs ≥3.15 minimum (4.15 recommended) — 3.18 boots tainted |

Corrections to earlier assumptions:
- **The kernel is NOT the wall.** systemd v252–v257 README: *"Linux kernel ≥ 3.15"*
  minimum, 4.15 recommended. 3.18 meets the minimum (runs with `old-kernel` taint).
- **The real wall is merged-/usr**, which is exactly what defeated the earlier
  Ubuntu *jammy* attempt ("cant use usrmerge, cant redo the /bin dir").

---

## 1. What the original `reinstall.sh` actually is

It is a **userland swap**, *not* a kernel replacement:
- It only rewrites `/etc/apt/sources.list` and `apt upgrade`s through
  Debian stretch → Ubuntu xenial → bionic → focal.
- It **never touches `boot` (p42) or the kernel** — the vendor kernel and the
  Android boot image stay intact. That is why it works at all, and why it stops
  dead once a target needs merged-/usr (bookworm/jammy and later).

`jammy` is commented out in the script for exactly this reason:
> *"This area will halfway break the system. It cant use usrmerge, cant redo the
> /bin dir. apt update shows the system is up2date, but any attempts to install
> additional software, you get complaints from apt."*

---

## 2. The merged-/usr attempt (and why it failed)

Ran Debian's `usrmerge` package (v25) on the device.

**What it does:** converts `/bin`, `/sbin`, `/lib` (and `/lib64`, etc.) into
symlinks to `/usr/...`, moving contents into `/usr`.
`directories_to_merge()` → `unshift(@dirs, qw(bin sbin lib))`.

**Step 1 — file conversion: SUCCEEDED.** Every file in `/bin` now has its
counterpart in `/usr/bin` (`/usr/bin` is a superset), e.g.
`/bin/sh -> /usr/bin/sh`. No file was lost; the system stayed bootable.

**Step 2 — directory swap: FAILED.**
```perl
if (not rename($dir, "$dir~~delete~usrmerge~~")) {   # line ~242
    ...
    die "Can't rename $dir: $!";      #  -> "Invalid cross-device link"
}
```
Because `/` is an **overlayfs** and `/bin` is a **lower-layer** directory,
`rename()` returns `EXDEV`. The script then aborts.

Resulting state: `/bin`, `/sbin`, `/lib` are still **real directories**
(contents already symlinked into `/usr`), and dpkg shows `iF usrmerge`
(half-configured). System remains functional; `apt` still runs.

### The real problem for Debian 13
Debian 12+ does not merely *prefer* merged-/usr — it **depends** on it. A
half-merged system will produce broken package installs (the same symptom the
jammy note describes). So **blocker #1 must be solved structurally**, not by
re-running usrmerge.

### Options to actually merge `/usr` on an overlay root
1. **Bake the merged layout into the lower layer.** Rebuild/replace the
   `rootfs` (p44) squashfs image with a merged-/usr tree, and create the
   `/bin`,`/sbin`,`/lib` symlinks *there*. Overlay then presents them correctly
   and they're immutable — no rename needed.
2. **Create the symlinks directly in the upper layer.** In the overlay upper
   (`/mnt/.rwfs/data`), replace the corresponding dirs with symlinks. Needs the
   upper to carry a whiteout for the lower dirs (overlayfs semantics) — doable
   but fiddly and easy to get wrong.
3. **Abandon the overlay**: build a normal ext4 rootfs on `appdata` (p47) or the
   1 TB volume and point the kernel at it, keeping `boot`/kernel as-is. Biggest
   change, but gives a conventional, fully merged system.
4. **Skip the overlay only for the Debian 12 bootstrap** (debootstrap a merged
   tree into a directory/loop image and pivot), then install a boot image whose
   ramdisk points there.

---

## 3. cgroup version

```
/proc/cgroups  -> cgroup v1 controllers (cpuset,cpu,cpuacct,blkio,memory,...)
cgroup2 mounted: NO
```
The msm8953 3.18 vendor kernel has **no cgroup v2** support. systemd ≥ 252 will
run in a deprecated/hybrid mode; some newer unit features (e.g. `CgroupV2`,
unified `MemoryMax`) won't work. Not fatal, but a real limitation. A mainline
kernel (msm8953-mainline, ≥5.15/6.x) would bring cgroup v2, but that's the
kernel-port project (see §5).

---

## 4. Kernel & boot image mechanics (for any real upgrade)

- Boot image = **Android v0 bootimg**, page 4096:
  `[header][kernel section][ramdisk section]`
  - kernel section = `gzip(Image)` **followed by an appended DTB**
    (`0xd00dfeed` right after the gzip stream — verified: gzip consumes
    5,704,010 B of the 6,514,267 B section, leaving 810,257 B = the FDT).
- kernel_addr `0x80008000`, ramdisk_addr `0x81000000`, tags `0x80000100`.
- The **initramfs lives inside the boot image ramdisk**, and it carries the
  vendor modules (`usr/lib/modules/3.18.44-ui-qcom/`) plus the Ubiquiti
  boot scripts (`scripts/ubnt*`, `scripts/ubnt-init/apq8053/boot-emmc`).
  Those scripts mount `rootfs`(p44) + `overlay`(p46) and build the overlay root.
- To boot a *different* kernel: build for **msm8953**, append the DT, gzip, and
  repack into an Android boot image, then flash to **p42**.
  Source: `https://github.com/msm8953-mainline/linux` (mainline-close; postmarketOS
  ships `linux-postmarketos-qcom-msm8953`, e.g. 6.x). Feasible, but a real port.

---

## 5. Recommended path (in order of least risk)

1. **Today/quick win:** stay on the current Debian 11 kernel+userland; just purge
   UniFi packages and run services. (The 1 TB volume gives real storage.)
2. **Deiban 12/13, minimal change:** solve merged-/usr by option 1 or 3 (§2).
3. **Full modern system:** mainline msm8953 kernel (cgroup v2 + modern systemd),
   repack the boot image. This is the "real" project.

---

## 6. Recovery

- Full backup taken before any change (`backup.sh` → GPT + p42/p43/p44/p45/p46
  images on the 1 TB volume).
- Ubiquiti factory reset always available: recovery mode → `reset2defaults`.
- `ctrl_c` in `reinstall.sh` calls `ubnt-systool reset2defaults`.

---

## 7. Attempt log — 2026-10-01 (live test) and the lesson learned

**What worked:**
- `usrmerge` file-conversion phase **succeeded** — every `/bin`,`/sbin`,`/lib`
  entry became a symlink into `/usr/...`; `/usr/bin` became a superset.
  The system stayed fully functional through this.

**Where it broke — and the trap to avoid:**
- `usrmerge`'s directory swap then failed with `EXDEV` (overlayfs can't rename a
  lower-layer dir), so `/bin`,`/sbin`,`/lib` remained real directories.
- To finish it manually, the *correct* overlay method is:
  1. empty the dir (all entries are already symlinks),
  2. `rmdir` it (overlayfs creates a whiteout),
  3. `ln -s usr/<name> <name>`.
  This **worked for `/bin` and `/sbin`**.
- ❌ **FATAL MISTAKE:** for `/lib` we ran `find /lib -maxdepth 1 -type l -delete`
  *before* the swap. That deleted `/lib/ld-linux-aarch64.so.1` — the **dynamic
  linker** — and, because `/lib` had not yet been turned into a symlink, it was
  not replaced by the `/usr/lib` version. Result: **no dynamically-linked binary
  can `exec`** (not even the SSH shell). The device is unreachable except by
  physical recovery/reset.

**Rule:** when merging `/lib` on a non-merged system, **never delete its
top-level symlinks first.** Either (a) do the rmdir+symlink swap as a whole on a
system where `/lib` contents already live in `/usr/lib` (verify
`/lib/ld-linux-aarch64.so.1` and `/lib/<triplet>/` resolve into `/usr/lib`
**without** deleting them), or (b) create the `/lib -> usr/lib` symlink by
replacing the *directory itself* in one step. Keep a static `busybox` on the box
as a rescue shell before attempting this.

**Recovery:** physical — hold reset 30 s → recovery mode, then either repair the
`/lib` link on the `overlay` partition (p46) or `reset2defaults`.

---

## 8. Attempt #2 — 2026-10-01 22:55 CDT (live). The merge WORKED; the *check* broke it.

**Root cause of the first failure, now proven:** the dynamic linker and all of libc
live **only** in `/lib`, not `/usr/lib`:
`/lib/ld-linux-aarch64.so.1 -> aarch64-linux-gnu/ld-2.31.so`,
`/lib/aarch64-linux-gnu/libc-2.31.so`. A naive `/lib -> usr/lib` therefore loses
the linker *and* libc. `usrmerge`'s "file conversion" is what copies them first —
on this overlay system that step never completed, so the tree was never safe to swap.

**What worked this time (correct order):**
1. `do-merge.sh merge` — union-copied `/bin`,`/sbin`,`/lib` into `/usr/...` with
   `cp -a` (static busybox available as rescue). **Non-destructive.**
2. `do-merge.sh verify` — proved `/usr` is a **superset** of each dir and that
   `/usr/lib/ld-linux-aarch64.so.1`, `ld-2.31.so`, `libc-2.31.so`, `/usr/bin/sh`,
   `/usr/bin/ls`, `/usr/bin/busybox` all exist. **GATE passed.**
3. `do-merge.sh swap` — `busybox rm -rf /X` + `busybox ln -s usr/X /X` for each of
   `/bin`,`/sbin`,`/lib`. Result verified live:
   `ls -ld` → `/bin -> usr/bin`, `/sbin -> usr/sbin`, `/lib -> usr/lib`,
   `/lib64 -> ./lib`. **This is a successfully merged-/usr system.**

**What broke it — the self-inflicted part:**
- `check` ran the merged system and **passed the real tests**: `OK exec /bin/sh`,
  `OK dynamic shell`, `OK /bin/ls`.
- But it also ran *invalid* probes: `/bin/ls -c` and `/bin/busybox -c` (neither
  takes `-c`), which returned non-zero → the script **wrongly declared failure and
  auto-reverted**.
- The revert used `/usr/bin/mkdir`,`/usr/bin/date` — fine *before* the swap, but the
  swap had already made `/usr` the live tree, and the revert's ordering was wrong:
  it removed the `/lib` symlink without first rebuilding the directory, so `/lib`
  vanished → no process could `exec` → PAM/sshd auth dies (existing daemons keep
  serving, which is why HTTP/`/api/system` still answered 200).

**Lesson (bake into any future tool):**
1. **`check` must never mutate.** Diagnostics report; they do not "fix".
2. **Test with valid invocations** (`/bin/sh -c 'exit 0'`, `/bin/ls /`) — never a
   flag the tool does not accept; a bogus flag is indistinguishable from a broken lib.
3. **Revert ordering:** rebuild the real directory from `/usr/X` **first**
   (`mkdir X.revert; cp -a /usr/X/. X.revert/`), *then* remove the symlink, *then*
   `mv X.revert X`. Use static busybox for every step — never `/usr/bin/*` while
   mid-merge.
4. Once `swap` completes and the live tests pass, **stop** — the system is merged.
   Reboot to confirm; do not run anything else destructive.

**Corrected tool:** `do-merge.sh` (this repo) — `check` is now diagnostic-only and
`revert` is a separate, explicit, correctly-ordered command.

---

## 9. ✅ SUCCESS — 2026-10-02 04:14 CDT. merged-/usr achieved and survived reboot.

Ran the corrected `do-merge.sh` on a freshly reset box (root over keyboard-interactive SSH,
`192.168.12.198`, kernel `3.18.44-ui-qcom`, UniFi OS 3.0.0 / Debian 11 base).

- **merge** — union-copied `/bin`→`/usr/bin`, `/sbin`→`/usr/sbin`, `/lib`→`/usr/lib`.
  `/usr/bin` went 721 → 836 entries; the linker and libc are now in `/usr/lib`.
- **verify (gate)** — `RC=0`: `/usr/{bin,sbin,lib}` each a superset; the six make-or-break
  files present (`/usr/lib/ld-linux-aarch64.so.1`, `aarch64-linux-gnu/{ld-2.31.so,libc-2.31.so}`,
  `/usr/bin/{sh,ls,busybox}`).
- **swap** — `busybox rm -rf /X; busybox ln -s usr/X /X` for bin/sbin/lib →
  `/bin -> usr/bin`, `/sbin -> usr/sbin`, `/lib -> usr/lib`, `/lib64 -> ./lib`.
- **check (read-only)** — ALL PASSED: exec `/bin/sh`, dynamic shell, `/bin/ls`, `/bin/busybox`,
  `/usr/bin/{sh,ls}`, `ldd`, linker resolve, libc resolve.
- **reboot** — came back **merged**: `/bin/sh -> /usr/bin/dash`,
  `/sbin/init -> /usr/lib/systemd/systemd`,
  `/lib/ld-linux-aarch64.so.1 -> /usr/lib/aarch64-linux-gnu/ld-2.31.so`; `apt-get check` rc=0.

**This clears the blocker that killed the original `reinstall.sh` jammy stage
("can't use usrmerge, can't redo the /bin dir").** The copy-before-swap order is what makes
it safe — the naive `/lib -> usr/lib` first is what bricks it (see §7/§8).

Notes:
- `dpkg --audit` reports `ck-ui`, `node20`, `node24` missing their md5sums control file — a
  pre-existing UniFi OS quirk, **not** merge damage.
- The vendor kernel is unchanged (`3.18.44-ui-qcom`); no cgroup v2. Per the skill's rule, the
  kernel is **not** the wall for a Debian 12 userland — merged-/usr was, and it is now solved.

**Reproduce:** reset → SSH root → `cp -a /bin/busybox /busybox-static` →
`bash do-merge.sh merge && bash do-merge.sh verify && bash do-merge.sh swap && bash do-merge.sh check` → reboot.
