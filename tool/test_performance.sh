#!/usr/bin/env bash
# Runs integration_test/performance_test.dart on a connected PHYSICAL phone,
# iOS or Android, in profile mode. Simulators and emulators are refused: they
# run on the host's hardware, so their timings mean nothing for a phone.
#
# The phone's own library is browsed and only timed. The 12 MP fixture reaches
# the app over `adb reverse` (Android) or is copied into the app's Documents
# (iOS, left there for later runs); nothing touches the gallery.
# `flutter drive` uninstalls the app after a run, which would erase the
# owner's data, so the app is kept (--keep-app-running) and a normal release
# build is installed over the test build afterwards (HAYN_RESTORE_APP=0 skips).
# The screen must stay on and unlocked for the whole run.
# Usage: tool/test_performance.sh [flutter-device-id]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUNDLE_ID="app.naqaa.hayn"
TARGET="integration_test/performance_test.dart"
FIXTURES="$ROOT/build/perf-fixtures"
PHOTO_URL="https://upload.wikimedia.org/wikipedia/commons/c/cc/Mill_Creek_Canyon_Earthworks%2C_Double_Ring_Pond_-_2.jpg"
PHOTO_SHA=1bab9167b80213bfce142819e956933c359550eb15c4288fd63016e78f451dce

# Physical iOS/Android phones known to Flutter: "id<TAB>platform<TAB>name".
phones=$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
for d in json.load(sys.stdin):
    p = d["targetPlatform"]
    if not d["emulator"] and (p == "ios" or p.startswith("android")):
        print(d["id"], "ios" if p == "ios" else "android", d["name"], sep="\t")
')
if [ -n "${1:-}" ]; then
  line=$(printf '%s\n' "$phones" | awk -F'\t' -v id="$1" '$1 == id') || true
  if [ -z "$line" ]; then
    echo "$1 is not a connected physical phone (simulators and emulators are refused)." >&2
    exit 1
  fi
else
  line=$(printf '%s\n' "$phones" | head -1)
fi
if [ -z "$line" ]; then
  echo "Connect a physical iPhone or Android phone first." >&2
  exit 1
fi
IFS=$'\t' read -r DEVICE PLATFORM NAME <<<"$line"

# The 12 MP photo (CC0, iPhone 14 Plus, Display P3), pinned by SHA-256, and
# its HEIC/PNG copies: from Apple's encoders on macOS (make_perf_fixtures.swift),
# from libheif and Pillow elsewhere (make_perf_fixtures.py).
mkdir -p "$FIXTURES"
if [ ! -f "$FIXTURES/photo-12mp.jpg" ]; then
  curl -sfL -A "HaynDev (performance fixtures)" -o "$FIXTURES/photo-12mp.jpg" "$PHOTO_URL"
fi
# shasum on macOS (its sha256sum lacks -c); sha256sum on Linux.
if command -v shasum >/dev/null; then
  echo "$PHOTO_SHA  $FIXTURES/photo-12mp.jpg" | shasum -a 256 -c --quiet
else
  echo "$PHOTO_SHA  $FIXTURES/photo-12mp.jpg" | sha256sum -c --quiet
fi
if [ ! -f "$FIXTURES/photo-12mp.heic" ] || [ ! -f "$FIXTURES/photo-12mp.png" ] \
  || [ ! -f "$FIXTURES/photo-12mp-alpha.png" ]; then
  if [ "$(uname)" = Darwin ] && command -v swift >/dev/null; then
    swift test_native/make_perf_fixtures.swift "$FIXTURES"
    echo apple >"$FIXTURES/.generator"
  else
    # No Apple encoders here: libheif and Pillow write the same pixels, but the
    # HEIC bytes differ, so timings are comparable only within one generator.
    python3 test_native/make_perf_fixtures.py "$FIXTURES"
    echo libheif >"$FIXTURES/.generator"
  fi
fi
# A transparent HEIC (IMG-15) needs libheif through pillow-heif; without it
# the conversion test skips that row.
if [ ! -f "$FIXTURES/photo-12mp-alpha.heic" ]; then
  python3 test_native/make_perf_fixtures.py "$FIXTURES" --alpha-heic \
    || echo "No transparent HEIC fixture (needs pillow-heif); its row is skipped." >&2
fi
FILES=(photo-12mp.jpg photo-12mp.heic photo-12mp.png photo-12mp-alpha.png)
[ -f "$FIXTURES/photo-12mp-alpha.heic" ] && FILES+=(photo-12mp-alpha.heic)
# HAYN_PERF_LARGE=1 runs integration_test/large_image_test.dart instead: the
# same photo enlarged to about 200 MP, converted at full size (RUN-01).
if [ "${HAYN_PERF_LARGE:-}" = 1 ]; then
  TARGET="integration_test/large_image_test.dart"
  if [ ! -f "$FIXTURES/photo-200mp.jpg" ]; then
    python3 test_native/make_perf_fixtures.py "$FIXTURES" --large
  fi
  FILES=(photo-200mp.jpg)
fi

OUT="$ROOT/build/performance/$PLATFORM-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
# Which generator wrote the HEIC (files made before this note came from Apple).
{ cat "$FIXTURES/.generator" 2>/dev/null || echo apple; } >"$OUT/fixtures-generator.txt"
DEFINES=()
cleanup_platform() { :; }

if [ "$PLATFORM" = android ]; then
  ADB=(adb -s "$DEVICE")
  if [ "$("${ADB[@]}" shell getprop ro.kernel.qemu | tr -d '\r')" = 1 ]; then
    echo "$DEVICE is an emulator." >&2
    exit 1
  fi
  MODEL="$("${ADB[@]}" shell getprop ro.product.model | tr -d '\r')"
  PORT=8766
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FIXTURES" \
    >"$OUT/fixture-server.log" 2>&1 &
  SERVER=$!
  "${ADB[@]}" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
  DEFINES+=(--dart-define=HAYN_PERF_FIXTURES="http://127.0.0.1:$PORT")
  # The library is measured, so photo access is granted when the app asks.
  # shellcheck source=tool/android_photos.sh
  source "$ROOT/tool/android_photos.sh"
  allow_photos &
  WATCHER=$!
  cleanup_platform() {
    kill "$WATCHER" 2>/dev/null || true
    kill "$SERVER" 2>/dev/null || true
    "${ADB[@]}" reverse --remove "tcp:$PORT" 2>/dev/null || true
  }
  restore_app() {
    flutter build apk --release
    "${ADB[@]}" install -r build/app/outputs/flutter-apk/app-release.apk
  }
else
  MODEL="$(xcrun devicectl device info details --device "$DEVICE" 2>/dev/null \
    | awk -F': ' '/marketingName/ { print $2; exit }')"
  installed() {
    xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE_ID" \
      2>/dev/null | grep -q "$BUNDLE_ID"
  }
  # Files go into an existing app container, so install first when missing.
  if ! installed; then
    flutter build ios --profile
    xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
  fi
  for f in "${FILES[@]}"; do
    xcrun devicectl device copy to --device "$DEVICE" \
      --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
      --source "$FIXTURES/$f" --destination "Documents/perf-fixtures/$f" >/dev/null
  done
  DEFINES+=(--dart-define=HAYN_PERF_FIXTURES=documents)
  restore_app() {
    flutter build ios --release
    xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
  }
fi
DEFINES+=(--dart-define=HAYN_DEVICE_MODEL="$MODEL")

cleanup() {
  local status=$?
  cleanup_platform
  local report="$ROOT/build/integration_response_data.json"
  if [ -f "$report" ]; then
    mv "$report" "$OUT/report.json"
    python3 tool/performance_summary.py "$OUT/report.json" | tee "$OUT/summary.txt"
    echo "Report: $OUT"
  else
    echo "No test report written." >&2
  fi
  if [ "${HAYN_RESTORE_APP:-1}" = 1 ]; then
    echo "Installing a normal release build over the test build..."
    restore_app || echo "Could not reinstall the release build." >&2
  fi
  exit "$status"
}
trap cleanup EXIT
echo "Running on $NAME ($MODEL, $PLATFORM, $DEVICE)"
flutter drive --profile --keep-app-running -d "$DEVICE" \
  --driver test_driver/integration_test.dart --target "$TARGET" "${DEFINES[@]}"
