#!/usr/bin/env bash
set -euo pipefail

print_diagnostics() {
  adb logcat -d -s AndroidRuntime:E libc:F DEBUG:F VLC:V PlaybackDetection:E flutter:I | tail -120
}
trap print_diagnostics ERR

adb reverse tcp:8554 tcp:8554
adb install build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n net.zvektra.zvektra.whisper/net.zvektra.zvektra.MainActivity
for attempt in {1..75}; do
  if adb logcat -d -s flutter:I | grep -F 'ZVEKTRA_PLAYBACK_DETECTION_OK'; then
    echo 'Release APK rendered both authenticated RTSP routes and detected both classes from recorded playback.'
    exit 0
  fi
  if adb logcat -d -s flutter:I | grep -F 'Some tests failed.'; then
    echo 'The Android playback detection test reported a failure.'
    exit 1
  fi
  if ! adb shell pidof net.zvektra.zvektra.whisper >/dev/null; then
    echo 'The Android app closed during the release playback test.'
    print_diagnostics
    exit 1
  fi
  sleep 2
done
echo 'The release build did not finish the frame test.'
print_diagnostics
exit 1
