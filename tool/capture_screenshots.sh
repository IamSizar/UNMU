#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# capture_screenshots.sh
#
# Helper for grabbing App Store screenshots from the iOS Simulator.
# Apple requires the following device classes for a single submission:
#
#   iPhone 6.7" (iPhone 15 Pro Max) ............ 1290 × 2796
#   iPhone 6.5" (iPhone 11 Pro Max) ............ 1242 × 2688
#   iPhone 5.5" (iPhone 8 Plus) ................ 1242 × 2208
#   iPad 12.9"  (iPad Pro 12.9" 6th gen) ....... 2048 × 2732
#
# Usage:
#
#   ./tool/capture_screenshots.sh boot 6.7
#       Boots the recommended simulator for that size class.
#
#   ./tool/capture_screenshots.sh shot 6.7 dashboard
#       Captures the currently booted simulator's screen into
#       app_store/screenshots/iphone_67/dashboard.png
#
# Capture order recommended by Apple's review guidelines:
#   1. Hero / Discover
#   2. Stock detail with Shariah verdict
#   3. Expert post or community chat
#   4. Watchlist / Portfolio
#   5. Premium upgrade
#
# Drop each screenshot's slug in as the third argument so the saved
# filename reads as "01_hero.png", "02_stock_detail.png", etc.
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly OUT_DIR="$ROOT_DIR/app_store/screenshots"

device_for_size() {
  case "$1" in
    6.7) echo "iPhone 15 Pro Max" ;;
    6.5) echo "iPhone 11 Pro Max" ;;
    5.5) echo "iPhone 8 Plus" ;;
    12.9) echo "iPad Pro (12.9-inch) (6th generation)" ;;
    *) echo "" ;;
  esac
}

folder_for_size() {
  case "$1" in
    6.7) echo "iphone_67" ;;
    6.5) echo "iphone_65" ;;
    5.5) echo "iphone_55" ;;
    12.9) echo "ipad_129" ;;
    *) echo "" ;;
  esac
}

cmd_boot() {
  local size="${1:-}"
  local device
  device="$(device_for_size "$size")"
  if [[ -z "$device" ]]; then
    echo "unknown size class '$size' — expected 6.7 | 6.5 | 5.5 | 12.9" >&2
    exit 2
  fi
  echo "→ booting simulator: $device"
  xcrun simctl boot "$device" 2>/dev/null || true
  open -a Simulator
}

cmd_shot() {
  local size="${1:-}"
  local slug="${2:-}"
  local folder
  folder="$(folder_for_size "$size")"
  if [[ -z "$folder" ]]; then
    echo "unknown size class '$size'" >&2
    exit 2
  fi
  if [[ -z "$slug" ]]; then
    echo "missing slug — e.g. './tool/capture_screenshots.sh shot 6.7 dashboard'" >&2
    exit 2
  fi
  mkdir -p "$OUT_DIR/$folder"
  local target="$OUT_DIR/$folder/${slug}.png"
  xcrun simctl io booted screenshot --type=png "$target"
  echo "✓ saved $target"
}

cmd_list() {
  cat <<EOF
App Store screenshot size classes:

  6.7   iPhone 15 Pro Max         1290 x 2796   → $OUT_DIR/iphone_67/
  6.5   iPhone 11 Pro Max         1242 x 2688   → $OUT_DIR/iphone_65/
  5.5   iPhone 8 Plus             1242 x 2208   → $OUT_DIR/iphone_55/
  12.9  iPad Pro 12.9" (6th gen)  2048 x 2732   → $OUT_DIR/ipad_129/

Workflow:
  1. ./tool/capture_screenshots.sh boot 6.7
  2. flutter run -d "iPhone 15 Pro Max"
  3. ./tool/capture_screenshots.sh shot 6.7 01_discover
  4. Navigate the app, repeat 'shot' for each screen
EOF
}

main() {
  local cmd="${1:-list}"
  shift || true
  case "$cmd" in
    boot) cmd_boot "$@" ;;
    shot) cmd_shot "$@" ;;
    list|--help|-h) cmd_list ;;
    *) echo "unknown command '$cmd' — try 'list'" >&2; exit 2 ;;
  esac
}

main "$@"
