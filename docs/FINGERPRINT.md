# Fingerprint: Solar Assistant device identity on the UCK G2 Plus

## The wall

Solar Assistant's `influx-bridge-setup` derives a per-device identity used to bind the
box to an SA account. It reads that identity from hardware paths that exist only on the
boards SA ships on:

```
dep 1:  open("/dev/vcio", O_RDONLY)                    # Broadcom VideoCore (Raspberry Pi)
dep 2:  ioctl(fd, _IOC(READ|WRITE, 0x64, 0, 8))        # VideoCore mailbox property call
dep 3:  eth0 / wlan0 MAC
        plus /sys/class/sunxi_info/sys_info -> sunxi_serial  (Allwinner boards)
```

On the UCK G2 Plus (Qualcomm APQ8053 / Snapdragon 625, kernel 3.18.44-ui-qcom)
neither `/dev/vcio` nor `/sys/class/sunxi_info` exists. `strace` shows the exact failure:

```
openat("/dev/vcio", O_RDONLY) = 3                        # stub file satisfies dep 1
ioctl(3, _IOC(_IOC_READ|_IOC_WRITE, 0x64, 0, 0x8), ...) = -1 ENOTTY
write(1, "Failed to load dependency 2. Ple", 47) = 47
```

So dep 1 is a **plain file open** (fakeable) and dep 2 is a **kernel driver ioctl**
(not fakeable with a file).

## The fix (proven working 2026-10-03)

An `LD_PRELOAD` shim (`fingerprint/uck-vcio-shim.c`) intercepts `ioctl()` and answers the
VideoCore mailbox request with a value **derived from this device's own hardware**.

The seed is the **eMMC CID** (`/sys/block/mmcblk0/device/cid`) — factory-burned, unique per
chip, unchangeable. Fallback: `/etc/machine-id`.

Consequences:
- **Every unit yields a DIFFERENT identity** — no value is hardcoded, nothing is shared
  between devices. Safe to commit: the source contains no serials/MACs/device values.
- Setup then completes and writes `/usr/lib/influx-bridge/influx-bridge.env`:

```
DEV_UID="<derived>"
DEV_FID="<derived>"
DEV_S="<derived>"
SECRET_KEY_BASE="<generated>"
```

and `/usr/lib/frp/proxy.toml`, `/home/solar-assistant/region`.

Proven output on UCK #1 (CID `1501xxxxxxxxxxxxxx`): DEV_UID `93ab6cb6...`, DEV_FID `de497746...`,
DEV_S `ce8d5ab9...`.

## Wiring on the device

```
# build natively (aarch64) on the UCK — host gcc produces the wrong arch
gcc -shared -fPIC -O2 -o /usr/lib/influx-bridge/uck-vcio-shim.so uck-vcio-shim.c -ldl

# dep-1 stub (setup opens this before the ioctl)
[ -e /dev/vcio ] || { head -c 16 /dev/zero > /dev/vcio; chmod 600 /dev/vcio; }

# preload for both setup and the app
mkdir -p /etc/systemd/system/influx-bridge.service.d
cat > /etc/systemd/system/influx-bridge.service.d/10-vcio-shim.conf <<CONF
[Service]
Environment=LD_PRELOAD=/usr/lib/influx-bridge/uck-vcio-shim.so
CONF
systemctl daemon-reload
```

## Status / open item

- Fingerprint generation: **SOLVED + verified** (real DEV_UID written from the UCK's own CID).
- Remaining blocker: the precompiled Elixir release aborts with
  `Error: Erlang runtime mismatch. Was this project built on a different architecture?`
  NOT YET DIAGNOSED. Note: SA runs fine on Debian 13 **on a Pi**, so this is platform/
  architecture-specific, not an OS-version problem.

## SA hardening side-effects (do not misread as faults)

- `influx-bridge-setup` runs `/usr/bin/systemctl restart sshd`, moves SSH to **port 2222**,
  and drops `/etc/ssh/sshd_config.d/00-recovery.conf`:
    `PermitRootLogin no` + `AllowUsers solar-assistant`
  While that file is active, root SSH is refused before key auth runs
  (`User root ... not allowed because not listed in AllowUsers`).
  This looks exactly like "the box fell off the network" if you only probe port 22.
