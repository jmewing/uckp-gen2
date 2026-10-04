# Solar Assistant transplant onto the UCK G2 Plus (Debian 13)

Source image: `/srv/SolarSoftware/2024-08-14.img` (SA 1.9.15, aarch64, Debian 12 bookworm).
Extract/mount read-only, then stage the pieces. Target = Debian 13 trixie rootfs on UCK.

## Users + dirs

```
useradd -r -s /bin/false -d /var/lib/influxdb influxdb
useradd -r -m -d /home/solar-assistant -s /bin/bash solar-assistant
mkdir -p /usr/lib/influx-bridge /usr/lib/frp/conf.d /etc/influxdb /var/lib/influxdb
mkdir -p /home/solar-assistant/.config/solar-assistant /root/.config/solar-assistant
```

## Base deps (apt)

```
curl ca-certificates libargon2-1 psmisc dbus mosquitto libmosquitto1 libmodbus5
python3 python3-venv rsync unzip zip xz-utils zstd usbutils pciutils ethtool net-tools less file procps
```

- `libargon2-1` — influx-bridge-setup links `libargon2.so.1`.
- `psmisc` — SA calls `killall` (dmesg loop); `curl` — influxdb health script.
- **Do NOT install network-manager/wpa_supplicant**: SA's Pi image runs networking via
  `dhcpcd`/`systemd-networkd`, and `NetworkManager.conf` is `managed=false`; the UCK has no
  WiFi radio anyway. Installing NM risks fighting `ifupdown` on eth0.

## Files to push (from the image)

```
/usr/lib/influx-bridge/influx-bridge          # 15 MB Elixir release
/usr/lib/influx-bridge/influx-bridge-setup    # identity generator (see docs/FINGERPRINT.md)
/usr/lib/influx-bridge/signal.sh              # LED signalling; also runs setup --failed on stop
/usr/lib/influx-bridge/Mnesia.nonode@nohost/  # initial DB state
/usr/bin/influxd                              # InfluxDB 1.8.10
/usr/lib/influxdb/scripts/                    # influxd-systemd-start.sh (+ init.sh)
/etc/influxdb/influxdb.conf
/etc/default/influxdb
/usr/lib/frp/frpc + /etc/systemd/system/frpc.service
/etc/systemd/system/influxdb.service
/etc/systemd/system/influx-bridge.service     # EnvironmentFile=.../influx-bridge.env (must exist!)
/etc/systemd/system/influx-bridge-setup.service
```

**Gotcha:** `influx-bridge.service` has `EnvironmentFile=/usr/lib/influx-bridge/influx-bridge.env`.
If the file is missing the unit fails with "Failed to load environment files".
The env file is normally WRITTEN by influx-bridge-setup (DEV_UID/DEV_FID/DEV_S/SECRET_KEY_BASE).
`touch` it only as a stopgap; the shim is what makes setup actually produce it.

## Order

1. push binaries, unpack Mnesia + influxdb scripts, fix perms
2. `systemctl daemon-reload && systemctl enable influxdb frpc influx-bridge influx-bridge-setup`
3. build + install the vcio shim, stub /dev/vcio, wire LD_PRELOAD  (docs/FINGERPRINT.md)
4. run setup once under the shim -> writes influx-bridge.env + frp/proxy.toml + region
5. start influxdb (health: http://127.0.0.1:8086/health), then influx-bridge

## Known remaining blocker

`Error: Erlang runtime mismatch. Was this project built on a different architecture?`
The precompiled release aborts at boot on the UCK while the SAME SA runs on Debian 13 on a
Pi. Platform/architecture-specific — not yet diagnosed.
