# Debian 12 → 13 upgrade recipe (UCK-G2-Plus / UCKP, APQ8053)

Status: **12 boots and is known-good. 13 attempt HUNG the boot (2026-10-02 ~15:36).**
Plan: get to 12 → build a RESTORE IMAGE of the 12 state → only then attempt 13.

## Verified restore point (Debian 12, working)

`/srv/backups/uckp-gen2/uckp-bookworm-20261002-0655/` — all SHA256 OK:

    p42-boot.img   p43-recovery.img   p44-rootfs.img
    p45-persist.img   p46-overlay.img   gpt-backup.bin

Metadata: `os-release.txt` = Debian 12 (bookworm); `uname.txt` = 3.18.44-ui-qcom aarch64.
This is the golden image: restore these partitions → box is back on the known-good 12 state.

## The recipe (Jeremy's notes, 2026-10-02)

    # 1. Clear dpkg force-conf overrides (UniFi sets these; they block clean replacement)
    rm -rfv /etc/dpkg/dpkg.cfg.d/015*
    rm -rfv /etc/dpkg/dpkg.cfg.d/020*

    # 2. Neutralize postgresql prerm scripts (they abort the upgrade)
    cp /var/lib/dpkg/info/postgresql-16.prerm /var/lib/dpkg/info/postgresql-16.prerm.bak
    printf '#!/bin/sh\nexit 0\n' > /var/lib/dpkg/info/postgresql-16.prerm
    chmod 755 /var/lib/dpkg/info/postgresql-16.prerm
    cp /var/lib/dpkg/info/postgresql-14.prerm /var/lib/dpkg/info/postgresql-14.prerm.bak
    printf '#!/bin/sh\nexit 0\n' > /var/lib/dpkg/info/postgresql-14.prerm
    chmod 755 /var/lib/dpkg/info/postgresql-14.prerm

    # 3. Unmark + purge the UniFi app stack
    sudo dpkg-query -W -f='${binary:Package}\n' \
      | egrep "ucore|ustd*|ui-snmp|ustate-exporter|analytic-report-go|ble-http-transport|simple-pid|mongodb|postgresql|mongo" \
      | xargs -r sudo apt-mark auto && sudo apt autoremove --purge

    # 4. Upgrade in the SAFE ORDER
    sudo apt update
    sudo apt upgrade --without-new-pkgs     # <-- CRITICAL: existing pkgs first
    sudo apt full-upgrade

**Lesson learned 2026-10-02:** we went straight to `full-upgrade` and skipped
`upgrade --without-new-pkgs`. That is the step that prevents the half-migrated
mess that hung the trixie boot. Do not skip it.

## Keep vs purge (diffed from the verified 12 backup dpkg-list.txt)

### KEEP — boot-chain / essential (do NOT purge)

    cloudkey-plus-apq8053-base-files   5.1.144~1770+gaf464baa   "Cloud Base" — anchor pkg
    ubnt-tools                         5.1.11~556+g3abf3fe      provides ubnt-systool reset2defaults
    uck-tools                          0.0.2-3+g98e02456357e    Cloud Key series tools
    uos / uos-agent / uos-discovery-client                     UniFi OS CLI + agents

### PURGE — UniFi app stack (Jeremy's targets confirmed present)

    mongodb-server mongodb-server-core mongodb-clients
    postgresql-14 postgresql-client-14 postgresql-common postgresql-client-common
    libpq5
    temurin-25-jre adoptium-ca-certificates
    analytic-report-go ucore-setup-listener uled-control
    unifi unifi-core unifi-directory unifi-identity-update
    unifi-assets-uckp unifi-email-templates-all
    ucs-agent python3-unifi-console-protos

Already dead (rc/ic leftovers): ck-splash, ck-ui

### Safer purge pattern (guards the keep-list)

    dpkg-query -W -f='${binary:Package}\n' \
      | egrep -i 'unifi|ucore|uled|uos-discovery|ucs-agent|ustd|ui-snmp|ustate|analytic-report-go|ble-http-transport|simple-pid|mongodb|mongo|postgresql|temurin|adoptium|python3-unifi' \
      | grep -v 'cloudkey-plus-apq8053-base-files' \
      | xargs -r apt-mark auto

…then `apt autoremove --purge`.

## Filesystem layout note (squashfs + overlay) — KEEP IT

- p44 = rootfs squashfs (ro lower) — **this is what "factory reset" restores to**
- p46 = /mnt/.rwfs (rw upper) — all customizations live here; reset DROPS this
- p45 = /persistent — UniFi's user-data seed
- p47 = /data — bulk storage
- p43 = recovery (64 MB) — USB/recovery-mode flash payload

**"Reset to my custom state" = build a new squashfs from the current merged root
and write it to p44.** Then wiping the overlay restores YOUR system, not factory.
Do NOT edit p43 for this. Stage any new p44 on a spare partition and test-boot
before swapping the live one.

## Recovery mode (validated)

1. Cut power (supercapacitor — no battery, instant)
2. Hold reset button
3. Apply power, hold ~10s until LED loops blue → off → white
4. Browse to 192.168.12.198 (fallback 192.168.1.30)
5. Upload firmware (UCKP 0.8.6, or a Debian-12 image when we have one)

## SSH note

sshd on this box: `PasswordAuthentication no`, `ChallengeResponseAuthentication yes`.
Clients MUST offer keyboard-interactive, else sshd closes with no prompt:

    ssh -o PreferredAuthentications=keyboard-interactive,password root@192.168.12.198

## DNS note (fixed 2026-10-02)

/etc/resolv.conf was a dangling symlink → /run/systemd/resolve/stub-resolv.conf
with systemd-resolved INACTIVE → no DNS → apt could not resolve.
Fixed by replacing with a plain file:

    nameserver 192.168.12.1
    nameserver 1.1.1.1
    nameserver 8.8.8.8
