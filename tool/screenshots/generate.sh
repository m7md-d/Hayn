#!/usr/bin/env bash
# Regenerates the README screenshots in docs/screenshots/ from the real app in
# a throwaway iOS simulator. The simulator's library holds only the photos and
# videos in tool/screenshots/photos/. The app steps itself through the shots
# (tool/screenshots/app.dart) and says when each is on screen and settled; this
# script captures it, flips light/dark between captures, and deletes the
# simulator at the end.
#
# Extra arguments go to `flutter build` (e.g. --no-pub).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PHOTOS="$ROOT/tool/screenshots/photos"
OUT="$ROOT/docs/screenshots"
BUNDLE_ID="app.naqaa.hayn"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
WIDTH=804 # 2x the device's 402pt width: sharp on retina, light in git

shopt -s nullglob nocaseglob
media=("$PHOTOS"/*.{jpg,jpeg,png,heic,heif,webp,gif,mp4,mov,m4v})
shopt -u nocaseglob
if ((${#media[@]} == 0)); then
  echo "No photos in tool/screenshots/photos/ — add the images and videos the screenshots should show." >&2
  exit 1
fi

RUNTIME=$(xcrun simctl list runtimes available | awk '/^iOS/ { id = $NF } END { print id }')
if [ -z "$RUNTIME" ]; then
  echo "No iOS simulator runtime installed (Xcode → Settings → Components)." >&2
  exit 1
fi

echo "Building the app for the simulator…"
(cd "$ROOT" && flutter build ios --simulator --debug -t tool/screenshots/app.dart "$@")

UDID=$(xcrun simctl create "Hayn screenshots" "$DEVICE_TYPE" "$RUNTIME")
cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

boot() {
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b >/dev/null
}

echo "Preparing the simulator…"
boot
xcrun simctl install "$UDID" "$ROOT/build/ios/iphonesimulator/Runner.app"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID"
xcrun simctl shutdown "$UDID"

# Edited while the simulator is off, so nothing caches the old values.
DATA="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data"
# First boot seeds Apple's sample photos; drop them and the Photos database
# so the library holds only ours.
rm -rf "$DATA/Media/DCIM" "$DATA/Media/PhotoData"
# A new simulator copies the Mac's language; the README is in English.
plutil -replace AppleLanguages -json '["en-US"]' "$DATA/Library/Preferences/.GlobalPreferences.plist"
plutil -replace AppleLocale -string en_US "$DATA/Library/Preferences/.GlobalPreferences.plist"
# `simctl privacy grant` writes auth_version 1; iOS 26 treats that as never
# asked and prompts again, which nothing here can answer. Record the grant
# in the current format.
sqlite3 "$DATA/Library/TCC/TCC.db" "UPDATE access SET auth_value = 2, auth_reason = 2, \
  auth_version = 2 WHERE service = 'kTCCServicePhotos' AND client = '$BUNDLE_ID';"
boot

xcrun simctl addmedia "$UDID" "${media[@]}"
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100
xcrun simctl ui "$UDID" appearance light
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

HANDOFF="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Documents/screenshots"
mkdir -p "$OUT"

capture() { # <shot>-<light|dark>
  sleep 0.5 # iOS animates the status bar's colour after the app's theme
  xcrun simctl io "$UDID" screenshot --type=png --mask=alpha "$OUT/$1.png" >/dev/null 2>&1
  sips --resampleWidth "$WIDTH" "$OUT/$1.png" >/dev/null
}

echo "Capturing…"
deadline=$((SECONDS + 300))
until [ -f "$HANDOFF/finished" ]; do
  for ready in "$HANDOFF"/*.ready; do
    tag=$(basename "$ready" .ready)
    capture "$tag"
    # The app waits for this switch before its next hand-over.
    case "$tag" in
      *-light) xcrun simctl ui "$UDID" appearance dark ;;
      *) xcrun simctl ui "$UDID" appearance light ;;
    esac
    rm -f "$ready"
    touch "$HANDOFF/$tag.done"
    echo "  $tag"
  done
  if ((SECONDS > deadline)); then
    xcrun simctl io "$UDID" screenshot "$ROOT/build/screenshots-failure.png" >/dev/null 2>&1 || true
    echo "Timed out waiting for the app. The simulator's screen at that moment:" >&2
    echo "  build/screenshots-failure.png" >&2
    exit 1
  fi
  sleep 0.3
done
echo "Screenshots written to docs/screenshots/."
