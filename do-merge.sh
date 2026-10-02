#!/bin/bash
# do-merge.sh — correctly merge /bin,/sbin,/lib into /usr on an overlayfs root.
#
#   bash do-merge.sh merge   # phase 1: copy content into /usr (NON-destructive)
#   bash do-merge.sh verify   # phase 2: prove /usr holds a superset (GATE)
#   bash do-merge.sh swap     # phase 3: rm dir + symlink it (static busybox)
#   bash do-merge.sh check    # phase 4: DIAGNOSTIC ONLY (no auto-revert!)
#   bash do-merge.sh revert    # manual, safe revert (static busybox)
#
# Design rules learned the hard way (2026-10-01):
#   * Every destructive op runs under the STATIC busybox ($BB). A half-merged
#     /usr must never take away our ability to finish — or to revert.
#   * `check` NEVER mutates. The first version auto-reverted on a bad test and
#     destroyed a perfectly good merged system. Diagnostics report; they do not act.
#   * `revert` must rebuild the dir from /usr *before* removing the symlink, and
#     must use $BB for rm/mkdir/cp — never /usr/bin/*.
set -uo pipefail
BB="${BB:-/busybox-static}"
[ -x "$BB" ] || { echo "FATAL: static busybox missing at $BB"; exit 1; }
log(){ echo "[$(date +%T)] $*"; }

merge_dir() { # SRC DST  (union; SRC wins on name collision)
  local src="$1" dst="$2" e b
  for e in "$src"/* "$src"/.[!.]* "$src"/..?*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    b=${e##*/}
    if [ -L "$e" ]; then
      rm -rf "$dst/$b"; cp -a "$e" "$dst/$b"
    elif [ -d "$e" ]; then
      if [ -d "$dst/$b" ] && [ ! -L "$dst/$b" ]; then merge_dir "$e" "$dst/$b"
      else rm -rf "$dst/$b"; cp -a "$e" "$dst/$b"; fi
    else
      rm -rf "$dst/$b"; cp -a "$e" "$dst/$b"
    fi
  done
}

phase_merge() {
  for n in bin sbin lib; do
    [ -L "/$n" ] && { log "/$n already a symlink, skip"; continue; }
    log "MERGE /$n -> /usr/$n"; merge_dir "/$n" "/usr/$n"
  done
  log "merge phase done"
}

phase_verify() {
  local rc=0 n miss
  for n in bin sbin lib; do
    [ -L "/$n" ] && continue
    miss=$(cd "/$n" && find . -mindepth 1 | while read -r p; do
             [ -e "/usr/$n/$p" ] || [ -L "/usr/$n/$p" ] || echo "$p"; done)
    if [ -n "$miss" ]; then log "FAIL /usr/$n missing:"; echo "$miss" | head -30; rc=1
    else log "OK  /usr/$n superset of /$n"; fi
  done
  for f in /usr/lib/ld-linux-aarch64.so.1 /usr/lib/aarch64-linux-gnu/ld-2.31.so \
           /usr/lib/aarch64-linux-gnu/libc-2.31.so /usr/bin/sh /usr/bin/ls /usr/bin/busybox; do
    if [ -e "$f" ] || [ -L "$f" ]; then log "OK  present: $f"
    else log "FAIL missing: $f"; rc=1; fi
  done
  return $rc
}

phase_swap() {
  for n in bin sbin lib; do
    [ -L "/$n" ] && { log "/$n already merged"; continue; }
    log "SWAP /$n -> usr/$n"
    "$BB" rm -rf "/$n"
    "$BB" ln -s "usr/$n" "/$n"
  done
  log "swap phase done"; ls -ld /bin /sbin /lib /lib64
}

# --- diagnostic only. NO mutation. ---
phase_check() {
  local rc=0
  exec_test(){ if eval "$1" >/dev/null 2>&1; then log "OK   $2"; else log "FAIL $2"; rc=1; fi; }
  exec_test "/bin/sh -c 'exit 0'"                  "exec /bin/sh"
  exec_test "/bin/sh -c 'echo x >/dev/null'"       "exec dynamic /bin/sh"
  exec_test "/bin/ls /"                            "exec /bin/ls"
  exec_test "/bin/busybox echo ok"                 "exec /bin/busybox"
  exec_test "/usr/bin/sh -c 'exit 0'"              "exec /usr/bin/sh"
  exec_test "/usr/bin/ls /"                        "exec /usr/bin/ls"
  exec_test "ldd /bin/ls"                          "library resolution (ldd)"
  [ -e /lib/ld-linux-aarch64.so.1 ] && log "OK   /lib/ld-linux-aarch64.so.1 resolves" || { log "FAIL linker"; rc=1; }
  [ -e /lib/aarch64-linux-gnu/libc-2.31.so ] && log "OK   libc resolves" || { log "FAIL libc"; rc=1; }
  [ $rc = 0 ] && log "ALL CHECKS PASSED" || log "CHECKS FAILED (diagnostic only — nothing changed)"
  return $rc
}

# --- manual revert. Rebuild dir from /usr FIRST, then drop the symlink. ---
revert_one() {
  local n="$1"; [ -L "/$n" ] || { log "/$n not a symlink, skip"; return; }
  [ -d "/usr/$n" ] || { log "FATAL: /usr/$n missing, refusing to revert /$n"; return 1; }
  "$BB" mkdir -p "/${n}.revert"
  "$BB" cp -a "/usr/$n/." "/${n}.revert/"
  "$BB" rm -f "/$n"
  "$BB" mv "/${n}.revert" "/$n"
  log "reverted /$n (now a real dir from /usr/$n)"
}

phase_revert() {
  log "REVERT requested — restoring /bin /sbin /lib as real directories"
  for n in bin sbin lib; do revert_one "$n" || log "revert of /$n had problems"; done
  ls -ld /bin /sbin /lib /lib64
}

case "${1:-}" in
  merge) phase_merge;;
  verify) phase_verify;;
  swap) phase_swap;;
  check) phase_check;;
  revert) phase_revert;;
  *) echo "usage: $0 {merge|verify|swap|check|revert}"; exit 2;;
esac
