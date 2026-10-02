#!/usr/bin/env bash
# Sourced by tool/test_android_device.sh and tool/test_performance.sh; needs
# the ADB array (adb -s <serial>) set by the caller.
#
# Taps "Allow all" (or "Allow") in the photo permission dialog, found by id.
# flutter drive installs the app afresh each run, so the app asks for photo
# access; an unanswered dialog left the real-app test paused until it failed
# (2026-10-02), and the performance test waited for the phone's owner. The
# user decided the scripts answer it themselves (2026-10-02).
# uiautomator turns accessibility on, which Flutter's test binding reports as
# a leaked SemanticsHandle, so it runs only while the dialog has focus.
allow_photos() {
  local ids="permission_allow_all_button|permission_allow_button"
  for _ in $(seq 1 600); do
    if ! "${ADB[@]}" shell dumpsys window 2>/dev/null \
      | grep -q 'mCurrentFocus=.*permissioncontroller'; then
      sleep 1
      continue
    fi
    local node
    node=$("${ADB[@]}" exec-out uiautomator dump /dev/tty 2>/dev/null \
      | tr '>' '\n' | grep -E "resource-id=\"[^\"]*($ids)\"" | head -1) || true
    if [ -n "$node" ]; then
      read -r x1 y1 x2 y2 < <(echo "$node" \
        | sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/')
      "${ADB[@]}" shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
      echo "Tapped the photo permission dialog."
      return
    fi
    sleep 1
  done
}
