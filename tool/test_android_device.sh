#!/usr/bin/env bash
# Runs integration_test/android_device_test.dart on a connected Android phone,
# in profile mode so DarkLib's Rust code is optimized (a debug build needs over
# ten minutes for one gain-map AVIF encode). Android 16 hides files adb pushes
# into the app's directories, so fixtures are served from this computer over
# `adb reverse` (127.0.0.1 only) and artifacts come back in the drive report.
# The photo permission the app asks for is answered "Allow all" (user
# decision 2026-10-02: the library is read, as the performance test reads it).
# Nothing is written to the phone's storage or gallery, unless HAYN_GALLERY=1:
# then the crop tests ask for photo access, this script taps "Allow all" in
# the system dialog (flutter drive reinstalls the app, so `pm grant` cannot
# precede the run), and the sources and results are saved to the gallery.
# Those files are left for the phone's owner to remove. The screen must be on.
# Usage: [HAYN_GALLERY=1] tool/test_android_device.sh [adb-serial]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TARGET="${HAYN_TEST_TARGET:-integration_test/android_device_test.dart}"
SERIAL="${1:-$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')}"
if [ -z "$SERIAL" ]; then
  echo "Connect an Android phone with USB debugging first." >&2
  exit 1
fi
ADB=(adb -s "$SERIAL")
PORT=8765
DEFINES=(--dart-define=HAYN_FIXTURES="http://127.0.0.1:$PORT")
if [ "${HAYN_GALLERY:-}" = 1 ]; then
  DEFINES+=(--dart-define=HAYN_GALLERY=true)
fi

# shellcheck source=tool/android_photos.sh
source "$ROOT/tool/android_photos.sh"
STRIP="native/darklib/target/tmp"
if [ ! -d "$STRIP/strip-orientation-sources" ]; then
  (cd native/darklib && cargo test --locked --test strip_orientation)
fi

OUT="$ROOT/build/android-device/$(date +%Y%m%d-%H%M%S)"
STAGE="$OUT/fixtures"
mkdir -p "$STAGE/strip-sources" "$STAGE/strip-expected"
cp native/darklib/tests/fixtures/*.{avif,heic,jpg,png} "$STAGE/"
cp "$STRIP/strip-orientation-sources/"* "$STAGE/strip-sources/"
cp "$STRIP/strip-orientation/"* "$STAGE/strip-expected/"
if [ -n "${HAYN_EXTRA_FIXTURES:-}" ]; then
  cp -R "$HAYN_EXTRA_FIXTURES" "$STAGE/"
fi

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$STAGE" \
  >"$OUT/fixture-server.log" 2>&1 &
SERVER=$!
cleanup() {
  kill "$SERVER" 2>/dev/null || true
  [ -n "${WATCHER:-}" ] && kill "$WATCHER" 2>/dev/null || true
  "${ADB[@]}" reverse --remove "tcp:$PORT" 2>/dev/null || true
  local report="$ROOT/build/integration_response_data.json"
  if [ -f "$report" ]; then
    python3 - "$report" "$OUT/results" <<'EOF'
import base64, json, os, sys
data = json.load(open(sys.argv[1]))
out = sys.argv[2]
for name, b64 in data.pop("artifacts", {}).items():
    path = os.path.join(out, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(base64.b64decode(b64))
os.makedirs(out, exist_ok=True)
json.dump(data, open(os.path.join(out, "report.json"), "w"), indent=2)
EOF
    rm "$report"
    echo "Test artifacts: $OUT/results"
  else
    echo "No test report written." >&2
  fi
}
trap cleanup EXIT
"${ADB[@]}" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
echo "Running on $SERIAL: $("${ADB[@]}" shell getprop ro.product.model)," \
  "Android $("${ADB[@]}" shell getprop ro.build.version.release)"
allow_photos &
WATCHER=$!
flutter drive --profile --no-pub -d "$SERIAL" \
  --driver test_driver/integration_test.dart --target "$TARGET" "${DEFINES[@]}"
