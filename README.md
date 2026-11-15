# Zvektra Android — verified test APK

[Download the APK artifact](https://github.com/pierre123bh/Zvektra/actions/runs/43743354767/artifacts/14172579212)

[Successful GitHub Actions run](https://github.com/pierre123bh/Zvektra/actions/runs/43743354767)

Built November 15, 2026 from commit `79e9c78dc75e7dff52f9a3686b10105ccac21748`.
Dart analysis, three URL tests, Android compilation and APK ZIP integrity checks passed.
Unzip the artifact and install `app-debug.apk`. GitHub sign-in may be required.
This is a debug-signed test APK; phone/NVR functionality remains unverified.

The generated Android platform and resolved dependency lockfile are included in
this repository. Use Flutter 3.29.3 and Java 17, then `flutter pub get`,
`flutter test`, and `flutter build apk --debug`. GitHub Actions performs these
steps automatically on pushes to main. No device credentials or signing keys
are included. See [TESTING.md](TESTING.md) for implemented and unfinished features.

## Original source archive notes (historical)

The notes below describe the archive before its first successful Android build.
Their statement that no APK has been compiled is superseded by the verified run above.

# ZVEKTRA — new Flutter Android project (v0.1 source)

## What is implemented
- Jarvis-style assistant screen, text command parsing and microphone UI.
- Up to 5 NVR configurations, add/edit/save/delete with confirmation.
- Fixed host `zvektra.net`; configurable **Zvektra Port**, blank for new devices, 1–5 digits, validated 1–65535.
- Manufacturer, NVR name, username, password and maximum channels per device.
- Password stored separately with `flutter_secure_storage`; metadata in SharedPreferences.
- RTSP playback via `flutter_vlc_player` with camera audio when stream supplies it.
- Dahua live and recorded RTSP URL construction based on user-verified format.
- Date/time recording selection, 30-second skip by reconnecting to a different playback start, pause/resume.
- Hikvision live URL candidate (NOT VERIFIED); explicit non-support messages for unverified playback protocols.

## Not yet implemented / not verified
- Offline Whisper model and inference. The current microphone prototype uses Android speech recognition; **it may require network access depending on device services**, so it does not meet the strict no-cloud voice requirement. Replace with an on-device whisper.cpp native bridge before claiming full offline operation.
- On-device person detection, decoded-frame extraction, snapshots, detection counting/history. These need Android native LibVLC decoded-frame callbacks + TFLite/ONNX model integration. The UI explicitly states they are not active.
- Multi-brand historical playback for Hikvision, Uniview, MEye. Different models require device-specific RTSP/ONVIF/vendor support; only Dahua URL verified.
- End-to-end Android build and device test. Flutter SDK not installed in this environment.
- Secure transport: RTSP credentials in URL may be exposed to local logs/debugging; avoid logging URL, use VPN for remote access and rotate any previously shared NVR password.

## Build instructions
1. Install Flutter SDK and Android Studio, then run `flutter doctor`.
2. In a working folder run `flutter create --platforms=android zvektra`.
3. Copy `lib/main.dart` and `pubspec.yaml` from this archive into the generated project.
4. Add to `android/app/src/main/AndroidManifest.xml` (as direct children of `<manifest>`):
   `<uses-permission android:name="android.permission.INTERNET" />`
   `<uses-permission android:name="android.permission.RECORD_AUDIO" />`
   and (if using Android recognition) `<queries><intent><action android:name="android.speech.RecognitionService" /></intent></queries>`.
5. Run `flutter pub get`, then `flutter run` on an Android phone or `flutter build apk`.
6. Validate the `flutter_vlc_player` plugin version against your installed Flutter/Android Gradle environment and adjust as needed.
7. Configure a Dahua NVR with the working remote RTSP port and a **new/rotated password**. Test live and recorded playback.

## Next implementation milestones
1. Compile and verify Dahua playback in the app (not just standalone RTSP Player).
2. Native frame access + TFLite person detection, local snapshots and SQLite history.
3. whisper.cpp on-device model for truly offline voice commands.
4. Vendor-specific recorded playback adapters and tests for Hikvision/Uniview/MEye.
5. Security hardening, network resilience, UI polish and release signing.

This is a **source-code foundation**, not a completed production APK. The user-tested Android RTSP Player success does not itself verify this Flutter integration.


## v0.2 command review update
- Voice recognition now populates an **editable** command field and does not auto-execute. User must tap Execute, or may discard the transcription.
- Text commands use the same execution path.
- Detection requests are represented in the UI, but no false detections are reported. Actual AI counting, snapshots and offline Whisper still require Android native modules and model files.
- No APK was compiled in this environment.
