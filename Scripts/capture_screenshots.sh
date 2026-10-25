#!/bin/bash
# Captures raw App Store screens in every language from the Debug screenshot mode.
#   Scripts/capture_screenshots.sh <path to KACCoachingLog.app built for the simulator> [iphone|ipad]
# Output: docs/screenshots/raw/<device>/<lang>/<n>-<screen>.png
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
ONLY="${2:-}"
BUNDLE=com.leeo.KACCoachingLog
# Dedicated clean simulators, so no other app's back link shows in the status bar.
DEVICES=("iphone:iPhone 18 Pro Max" "ipad:iPad Pro 13-inch (M5)")
SCREENS=("1-list:" "2-recording:recording" "3-detail:detail" "4-settings:settings" "5-export:export")

device() {
  local name="Screenshots $1"
  xcrun simctl list devices available | grep -F "$name (" | grep -oE '[0-9A-F-]{36}' | head -1 \
    || xcrun simctl create "$name" "$1"
}

for entry in "${DEVICES[@]}"; do
  name="${entry%%:*}"
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  id="$(device "${entry#*:}")"
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" >/dev/null
  xcrun simctl ui "$id" appearance light
  xcrun simctl status_bar "$id" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4
  xcrun simctl install "$id" "$APP"
  for lang in ko en; do
    region=$([ "$lang" = ko ] && echo ko_KR || echo en_US)
    # Korean screens show a KCA credential, English screens an ICF one.
    cert=$([ "$lang" = ko ] && echo kac || echo acc)
    out="docs/screenshots/raw/$name/$lang"; mkdir -p "$out"
    # The iPad status bar shows the date in the device language, so switch the whole simulator.
    if [ "$(xcrun simctl spawn "$id" defaults read -g AppleLocale 2>/dev/null)" != "$region" ]; then
      xcrun simctl spawn "$id" defaults write -g AppleLanguages -array "$lang"
      xcrun simctl spawn "$id" defaults write -g AppleLocale "$region"
      xcrun simctl shutdown "$id"; xcrun simctl boot "$id"; xcrun simctl bootstatus "$id" >/dev/null
      xcrun simctl status_bar "$id" override --time "9:41" --batteryState charged --batteryLevel 100 \
        --wifiBars 3 --cellularMode active --cellularBars 4
    fi
    for screen in "${SCREENS[@]}"; do
      file="${screen%%:*}"; target="${screen#*:}"
      [ -s "$out/$file.png" ] && continue   # already captured; delete the file to retake
      seed=$([ "$target" = detail ] && echo -screenshotSeedWithError || echo -screenshotSeed)
      args=(-AppleLanguages "($lang)" -AppleLocale "$region" "$seed" -screenshotCert "$cert")
      [ -n "$target" ] && args+=(-screenshotScreen "$target")
      xcrun simctl launch --terminate-running-process "$id" "$BUNDLE" "${args[@]}" >/dev/null
      sleep 8
      xcrun simctl io "$id" screenshot "$out/$file.png" >/dev/null 2>&1
      echo "captured $out/$file.png"
    done
  done
done
