#!/usr/bin/env bash
set -euo pipefail

print_diagnostics() {
  adb logcat -d -s flutter:I PlaybackDetection:E BackgroundAgent:V AndroidRuntime:E libc:F DEBUG:F | tail -150
  adb logcat -d -s VLC:V | tail -40
}
trap print_diagnostics ERR

adb reverse tcp:8554 tcp:8554
adb reverse tcp:8085 tcp:8085
adb install -g build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n net.zvektra.zvektra.whisper/net.zvektra.zvektra.MainActivity
backgrounded=false
agent_backgrounded=false
for attempt in {1..110}; do
  if ! "$backgrounded" &&
     adb logcat -d -s flutter:I | grep -F 'ZVEKTRA_READY_FOR_BACKGROUND'; then
    adb shell input keyevent KEYCODE_HOME
    for transition in {1..20}; do
      if adb logcat -d -s flutter:I | grep -F 'ZVEKTRA_BACKGROUND_CONFIRMED'; then break; fi
      sleep 0.25
    done
    adb shell am start -W -n net.zvektra.zvektra.whisper/net.zvektra.zvektra.MainActivity
    backgrounded=true
  fi
  if ! "$agent_backgrounded" &&
     adb logcat -d -s flutter:I | grep -F 'ZVEKTRA_BACKGROUND_AGENT_STARTED'; then
    adb shell input keyevent KEYCODE_HOME
    for transition in {1..45}; do
      clips=$(adb shell ls /sdcard/Movies/Zvektra 2>/dev/null || true)
      if echo "$clips" | grep -qE '^Zvektra-2024-11-15_.*-Cam2-Person.*\.mp4' &&
         echo "$clips" | grep -qE '^Zvektra-2024-11-15_.*-Cam2-Vehicle.*\.mp4'; then
        agent_backgrounded=true
        break
      fi
      sleep 1
    done
    if ! "$agent_backgrounded"; then
      echo 'Background Agent did not publish both event types while the app was offscreen.'
      exit 1
    fi
    adb shell am start -W -n net.zvektra.zvektra.whisper/net.zvektra.zvektra.MainActivity
  fi
  if adb logcat -d -s flutter:I | grep -F 'ZVEKTRA_PLAYBACK_DETECTION_OK'; then
    "$agent_backgrounded"
    echo 'Release APK rendered both authenticated RTSP routes and detected both classes from recorded playback.'
    exit 0
  fi
  if adb logcat -d -s flutter:I | grep -F 'Some tests failed.'; then
    echo 'The Android playback detection test reported a failure.'
    print_diagnostics
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
