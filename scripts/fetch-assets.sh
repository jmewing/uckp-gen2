#!/bin/bash
# =============================================================================
# fetch-assets.sh — download every artifact needed to build/flash Debian 13
#                   on the UCK G2 Plus.
#
#   ./fetch-assets.sh [destdir]        (default: ./assets)
#
# Sources:
#   * Our Debian 13 squashfs image + stock boot images  -> from OUR repo/release
#     (set ASSET_BASE_URL to the release URL; see README).
#   * Ubiquiti's stock firmware (for returning to stock) -> dl.ui.com (public).
# =============================================================================
set -euo pipefail
DEST="${1:-./assets}"
mkdir -p "$DEST"
cd "$DEST"

# --- our own artifacts (published release) ---------------------------------
# Set these to the real release URL once the repo has one:
ASSET_BASE_URL="${ASSET_BASE_URL:-}"

fetch() { # <url> <outfile> [sha256]
  local url="$1" out="$2" sha="${3:-}"
  if [ -f "$out" ]; then echo "have   $out"; else
    echo "get    $out"
    curl -fL --retry 3 -o "$out.part" "$url" && mv "$out.part" "$out"
  fi
  if [ -n "$sha" ]; then
    echo "$sha  $out" | sha256sum -c - || { echo "SHA MISMATCH: $out"; return 1; }
  fi
}

if [ -n "$ASSET_BASE_URL" ]; then
  fetch "$ASSET_BASE_URL/p44-trixie.squashfs" p44-trixie.squashfs \
        "cd9e0a9dce3f5c0326c72cb65ec849d13f9e2b230f9a0255a613bf9544f7b43b"
  fetch "$ASSET_BASE_URL/p42-boot.img"        p42-boot.img
  fetch "$ASSET_BASE_URL/p43-recovery.img"    p43-recovery.img
else
  echo "NOTE: ASSET_BASE_URL not set — skipping our artifacts."
  echo "      Copy p44-trixie.squashfs here manually, or set the release URL."
fi

# --- Ubiquiti stock firmware (to get back to stock Debian 11) ---------------
# v0.8.6 is the documented recovery image (old layout, more free space).
STOCK_FW_URL="${STOCK_FW_URL:-https://dl.ui.com/unifi/firmware/UCKP/UCKP.apq8053.v0.8.6.8cf5792.181017.0942.bin}"
fetch "$STOCK_FW_URL" UCKP-stock-v0.8.6.bin || echo "(stock fw download failed — optional)"

echo
echo "== assets in $(pwd) =="
ls -la
