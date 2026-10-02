#!/bin/bash
# panel-state.sh — set the UCKP front panel (LED + 160x60 OLED) to a boot state.
#
#   panel-state.sh <state> [text...]
#
# States map to LED + LCD output. Callable from initramfs, systemd units, or a
# watchdog. Every call is best-effort: a panel failure must NEVER abort boot.
#
#   state      LED                                  LCD
#   ---------  -----------------------------------  --------------------------
#   boot       solid blue                           "Booting..."
#   boot:<n>   solid blue                           "Boot <n>"  (checkpoint)
#   ok         solid green                          "<text or IP>"
#   ready      fw configured (green)                "<text>"
#   warn       solid amber                          "<text>"
#   fail       solid red (breathing)                "FAIL: <text>"
#   recovery   fw recovery                          "RECOVERY"
#   setup      fw setup                             "SETUP"
#   reset      fw reset                             "RESETTING"
#   upgrade    fw upgrade                           "UPDATING"
#   off        LEDs off                             (unchanged)
#
# Requires: uled-ctrl (libuled) for LED; fbwrite.sh (+python3) for LCD.
# LCD requires ck-ui stopped to free /dev/fb0 (see free_fb()).
set -u

ULED="${ULED:-/usr/bin/uled-ctrl}"
FBWRITE="${FBWRITE:-$(dirname "$0")/fbwrite.sh}"
CKUI_STOP="${CKUI_STOP:-1}"   # stop ck-ui to free the framebuffer

led() { [ -x "$ULED" ] || return 0; "$ULED" "$@" >/dev/null 2>&1 || true; }
lcd() { [ -x "$FBWRITE" ] || return 0; "$FBWRITE" "$@" >/dev/null 2>&1 || true; }

free_fb() {
  [ "$CKUI_STOP" = 1 ] || return 0
  systemctl stop ck-ui >/dev/null 2>&1 || true
  sleep 1
}

state="${1:-}"; shift 2>/dev/null || true
text="$*"

case "$state" in
  boot|booting)   led color 0000ff; free_fb; lcd "Booting...";;
  boot:*)         led color 0000ff; free_fb; lcd "Boot ${state#boot:}";;
  ok)             led color 00ff00; free_fb; lcd "${text:-Deck ok}";;
  ready)          led fw configured; free_fb; lcd "${text:-Ready}";;
  warn)           led color ff8000; free_fb; lcd "${text:-WARN}";;
  fail|failed)    led breath 2 ff0000; free_fb; lcd "FAIL" "${text:-unknown}";;
  recovery)       led fw recovery; free_fb; lcd RECOVERY;;
  setup)          led fw setup;   free_fb; lcd SETUP;;
  reset)          led fw reset;   free_fb; lcd RESETTING;;
  upgrade)        led fw upgrade; free_fb; lcd UPDATING;;
  locate)         led blink 500 ff00ff 000000;;
  off)            led off;;
  *)              echo "usage: $0 {boot[:n]|ok|ready|warn|fail|recovery|setup|reset|upgrade|locate|off} [text]" >&2
                  exit 2;;
esac
exit 0
