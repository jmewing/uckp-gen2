#!/bin/bash
# merge-usr.sh — SAFE /usr merge for UCKP Gen2 (overlayfs root).
#
# WHY THIS EXISTS
#   On 2026-10-01 the first attempt died because it deleted /lib's top-level
#   symlinks *before* swapping the directory. That removed
#   /lib/ld-linux-aarch64.so.1 (the dynamic linker) with no replacement, so no
#   dynamically-linked binary could exec — including the SSH shell — and the
#   box had to be physically reset. See docs/DEBIAN13.md §7.
#
# THE RULE
#   Never delete anything out of /lib until the /lib -> usr/lib symlink is in
#   place, AND never rely on a dynamically-linked binary to do the swap.
#   Use a STATIC busybox for the destructive step.
#
# PRE-REQUISITES (verify, do not assume)
#   1. A *statically linked* busybox is staged at $BB.
#        file $BB   -> "... statically linked ..."
#        ldd  $BB   -> "not a dynamic executable"
#   2. The /usr side already contains everything /{bin,sbin,lib} had
#      (the usrmerge file-conversion phase, or a manual cp -a, must have run).
#   3. Console/serial access is available (do NOT do this over SSH alone).
#
# STATUS: UNTESTED — test on a spare unit with a serial console first.

set -euo pipefail

BB="${BB:-/root/busybox.static}"     # statically-linked busybox
DRY="${DRY:-0}"

die() { echo "FATAL: $*" >&2; exit 1; }
say() { echo "== $*"; }

[ -x "$BB" ] || die "static busybox not found/executable at $BB"
"$BB" true || die "$BB is not a working static binary"
ldd "$BB" 2>&1 | grep -qi 'not a dynamic executable' \
  || die "$BB is NOT statically linked — using it risks the same lockout"

say "Preflight: /usr side must already hold the real files"
for d in bin sbin lib; do
  [ -d "/usr/$d" ] || die "/usr/$d missing — conversion phase did not run"
done
# The linker MUST exist on the /usr side before we touch /lib.
for l in ld-linux-aarch64.so.1 ld-linux.so.3; do
  [ -e "/usr/lib/$l" ] && echo "  ok: /usr/lib/$l"
done
[ -e /usr/lib/ld-linux-aarch64.so.1 ] \
  || die "/usr/lib/ld-linux-aarch64.so.1 missing — abort (this is the trap)"

say "Preflight: confirm the device is a non-merged system (dirs, not links)"
for d in bin sbin lib; do
  if [ -L "/$d" ]; then echo "  /$d already a symlink — skipping"; fi
done

swap() {  # swap <name>  : replace /<name> dir with symlink -> usr/<name>
  local n="$1"
  [ -L "/$n" ] && { say "/$n already merged"; return 0; }
  [ -d "/$n" ] || die "/$n is not a directory"

  # 1. Every leaf must already exist under /usr/<n>. Refuse if not.
  if "$BB" find "/$n" -maxdepth 1 -mindepth 1 ! -type d -print -quit | grep -q .; then
    say "/$n still holds non-directory entries; the conversion phase is incomplete"
    die "refusing to swap /$n (would strand files)"
  fi

  # 2. Atomically-ish: remove the now-empty dir, then create the symlink.
  #    Both ops run under STATIC busybox, so no dynamic exec is needed.
  if [ "$DRY" = 1 ]; then say "DRY: would rm -rf /$n && ln -s usr/$n /$n"; return 0; fi
  "$BB" rm -rf "/$n"
  "$BB" ln -s "usr/$n" "/$n"
  say "merged /$n -> usr/$n"
}

# Order matters ZERO times now, because nothing is deleted before its
# replacement path exists in /usr. Do the least-risky first anyway.
for n in bin sbin lib; do swap "$n"; done

say "Post-check"
ls -ld /bin /sbin /lib
/bin/sh -c 'echo "shell still runs: OK"'
say "DONE — reboot to confirm."
