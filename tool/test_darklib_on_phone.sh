#!/usr/bin/env bash
# DarkLib tests that need the phone's CPU (Hayn PERF-05): the rav1d assembly
# per CPU feature (`tests/cpu_paths.rs`), each feature mask in its own
# process, so the paths a phone without dotprod or i8mm runs are checked on
# the one phone there is (user decision 2026-10-09: simulate the rest).
#
# Usage: tool/test_darklib_on_phone.sh [adb serial]   (default R5CY51L49KN)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERIAL="${1:-R5CY51L49KN}"
ADB=(adb -s "$SERIAL")
NDK="${ANDROID_NDK_HOME:-$(ls -d "$HOME/Android/Sdk/ndk/"* | sort -V | tail -1)}"
BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC_aarch64_linux_android="$BIN/aarch64-linux-android30-clang"
export AR_aarch64_linux_android="$BIN/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$BIN/aarch64-linux-android30-clang"
# shellcheck disable=SC1091
source "$HOME/.cargo/env"

cd "$ROOT/native/darklib"
EXE=$(cargo test --locked --release --target aarch64-linux-android --test cpu_paths \
  --no-run --message-format=json 2>/dev/null |
  python3 -c 'import json,sys
for l in sys.stdin:
    m = json.loads(l)
    if m.get("reason") == "compiler-artifact" and m.get("executable"):
        print(m["executable"])' | tail -1)
[ -n "$EXE" ] || { echo "No test binary built." >&2; exit 1; }

DIR=/data/local/tmp/darklib-test
"${ADB[@]}" shell rm -rf "$DIR"
"${ADB[@]}" shell mkdir -p "$DIR/fixtures"
"${ADB[@]}" push -q "$EXE" "$DIR/cpu_paths"
"${ADB[@]}" push -q tests/fixtures/*.avif "$DIR/fixtures/"
status=0
"${ADB[@]}" shell "cd $DIR && DARKLIB_FIXTURES=$DIR/fixtures ./cpu_paths --nocapture --test-threads=1" || status=$?
"${ADB[@]}" shell rm -rf "$DIR"
exit $status
