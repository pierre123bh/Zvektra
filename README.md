# Zvektra — Flutter Android (v2 source baseline)

This repository is being reset to the **latest Zvektra v2 command-review source from November 15, 2026**, not the earlier starter version.

## Implemented in v2 source
Jarvis-style assistant UI, editable typed commands and microphone UI; up to five NVRs with add/edit/save/delete; fixed `zvektra.net` hostname and blank Zvektra Port; maximum channels per device; secure password storage; Flutter VLC integration for Dahua live/recorded RTSP URLs; recording date/time selection and playback controls.

## Not yet implemented or verified
Offline Whisper (existing speech_to_text prototype is not guaranteed offline); native decoded-frame person counting and snapshots; simultaneous multi-NVR streams; Hikvision/Uniview/MEye recorded playback; Android build and device testing.

## Critical setup
The v2 source archive is `zvektra_v2_command_review.zip` from this conversation. The source files need to be imported into this repository. The original archive contains a Flutter Dart entry point and pubspec but not a complete generated Android platform directory. Generate the Android scaffolding with `flutter create --platforms=android .` in a properly configured Flutter workspace before building.

Do not commit NVR credentials, signing keys or RTSP URLs with passwords. The repository is currently public; consider changing its visibility to private.
