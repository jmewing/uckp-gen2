#!/bin/bash
# pull-backup.sh — pull the UCKP backup dir from the device to the server, verify.
set -uo pipefail
PW="$(cat /home/jmewing/.openclaw/workspace/.passwd)"
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1"
DEV=root@192.168.12.198
DEST=/srv/backups/uckp-gen2/uckp-backup-20261001-2233
mkdir -p "$DEST"
REMOTE="$(sshpass -p "$PW" ssh $SSHOPT "$DEV" 'ls -d /volume/*/uckp-backup-*' 2>/dev/null | tr -d '\r')"
echo "remote=$REMOTE"
for f in gpt-backup.bin gpt-print.txt SHA256SUMS p42-boot.img p43-recovery.img p44-rootfs.img p45-persist.img p46-overlay.img; do
  echo "== pulling $f ($(date +%T))"
  sshpass -p "$PW" ssh $SSHOPT "$DEV" "cat '$REMOTE/$f'" > "$DEST/$f.part" 2>/dev/null
  mv "$DEST/$f.part" "$DEST/$f"
  echo "   -> $(stat -c %s "$DEST/$f") bytes"
done
echo "== verify ($(date +%T))"
cd "$DEST" && sha256sum -c SHA256SUMS
echo "== DONE rc=$? ($(date +%T))"
