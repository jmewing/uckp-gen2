# Front panel: LED + OLED (UCK-G2-Plus)

## Hardware
- **OLED:** Visionox **SP8110** over SPI (`sp8110@0`, `!visionox,sp8110` in DTB),
  framebuffer `/dev/fb0`, **160x60 px, RGB565, rotate=180, 19200 bytes**.
  Driver `fb_sp8110`. Held by `ck-ui` (Qt) — must stop it to draw manually.
- **RGB LED:** `uled-ctrl` + `libuled.so.1` (`ui::uled`). UCKP class = `UCKPGpioLED`.
  sysfs: `/sys/class/leds/ulogo_ctrl`, `/sys/class/leds/mcu0/`,
  `/sys/class/leds/etherlight/`, `/sys/class/leds/ui-ese-{1,2}-ulogo_ctrl`.
- Config: `/data/unifi-core/config/settings.yaml` (ledSettings).
- Night-mode cron: `/etc/cron.d/led-night-mode-update` (runs `uled-ctrl fw idle`).

## uled-ctrl commands
    off
    color <rgb>                 # solid, e.g. aa00ff
    hsb <hsb>
    breath <seconds> <rgb>
    blink <ms> <rgb> [rgb]
    fw [status]                 # set by status, or query current
    reload                      # reload night mode

## fw status values
    idle  factory_default  configured  reboot  poweroff
    upgrade  setup  reset  locate  recovery  burnin  acting

Guards built in: setting to `idle` is refused during `booting` or `setup`.
Internal states seen: booting, configured, isSetup, reboot, setup, idle.

## Tools in this repo
- `fbwrite.sh` — draw text on the 160x60 OLED (takes /dev/fb0).
- `panel-state.sh <state> [text]` — set LED + LCD for a boot state in one call.

## Keep-list impact
`uled-ctrl` + `libuled.so.1` MUST be kept to retain LED control (they are UniFi
components but are the ONLY path to the RGB). `ck-ui` can be purged if replaced
by a custom framebuffer daemon using fbwrite.sh logic.
