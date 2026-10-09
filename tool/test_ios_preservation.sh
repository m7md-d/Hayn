#!/usr/bin/env bash
# Runs real platform tests on an isolated device using the installed runtime.
# Only this script's simulator is removed; build products stay on the project disk.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUNDLE_ID="app.naqaa.hayn"
# Another suite on the same throwaway device: integration_test/ios_region_test.dart.
TARGET="${1:-integration_test/ios_preservation_test.dart}"
RUNTIME=$(xcrun simctl list runtimes available | awk '/^iOS/ { id = $NF } END { print id }')
if [ -z "$RUNTIME" ]; then
  echo "Install an iOS simulator runtime in Xcode first." >&2
  exit 1
fi
# The bootstrap bundle only establishes a data container and Photos permission.
# flutter test always rebuilds the actual test target below.
if [ ! -d "$ROOT/build/ios/iphonesimulator/Runner.app" ]; then
  flutter build ios --simulator --debug --no-pub -t "$TARGET"
fi
UDID=$(xcrun simctl create "Hayn preservation tests" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro" "$RUNTIME")
cleanup() {
  local container
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null) || container=""
  if [ -n "$container" ] && [ -d "$container/Documents/preservation-results" ]; then
    local out="$ROOT/build/ios-preservation/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$out"
    if cp -R "$container/Documents/preservation-results/." "$out/"; then
      echo "Synthetic test artifacts: $out"
    else
      echo "Failed to export simulator test artifacts." >&2
    fi
  fi
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
boot() {
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b
}
boot
xcrun simctl install "$UDID" "$ROOT/build/ios/iphonesimulator/Runner.app"
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
mkdir -p "$CONTAINER/Documents/preservation-fixtures"
cp native/darklib/tests/fixtures/*.avif "$CONTAINER/Documents/preservation-fixtures/"
# The performance photo (tool/test_performance.sh fetches it), for the region suite.
if [ -f build/perf-fixtures/photo-12mp.jpg ]; then
  cp build/perf-fixtures/photo-12mp.jpg "$CONTAINER/Documents/preservation-fixtures/"
fi
xcrun simctl shutdown "$UDID"
# iOS 26 ignores simctl's legacy auth_version=1. Patch only our throwaway
# device, while offline, as in the existing screenshot runner.
TCC="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
sqlite3 "$TCC" "UPDATE access SET auth_value=2, auth_reason=2, auth_version=2 WHERE service='kTCCServicePhotos' AND client='$BUNDLE_ID';"
boot
echo "Running preservation tests on $UDID ($RUNTIME)"
flutter test "$TARGET" --no-pub -d "$UDID" --reporter expanded --no-uninstall
