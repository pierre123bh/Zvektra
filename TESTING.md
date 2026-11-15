# Android test build status

This source comes from `zvektra_v2_command_review.zip`, Library version 2,
SHA-256 `a3846d10dfdd795c1160a75f16a200b44df6a30a3bf8f043ad49ac88f8d5e68e`.
Compilation is verified only by a successful Actions run with an APK artifact.
No physical Android phone or NVR is connected to the build runner.

| Feature | Source status | Device verification |
| --- | --- | --- |
| Up to five named NVRs, fixed host, entered port, secure password storage | Implemented | Pending |
| Editable speech transcription, explicit Execute and Discard | Implemented using Android speech services | Pending; offline operation not guaranteed |
| Dahua live/recorded RTSP, video and stream audio | Implemented | Pending in this app; earlier external RTSP-player results are not app tests |
| Recording date/time picker, pause/resume, 30-second reconnection | Implemented | Pending |
| Hikvision live URL | Candidate implemented | Unverified |
| Hikvision recordings, Uniview and MEye streams | Not implemented; explicit unsupported message | Requires vendor adapters |
| Offline Whisper and Arabic/French command understanding | Not implemented; current command parser is English | Requires implementation |
| People appearance detection, timestamped snapshots/history | Not implemented; UI explicitly says inactive | Requires implementation |
| Adaptive grid for up to eight cameras | Not implemented; one player only | Requires implementation |
| Voice-specified from/to times or custom clip duration | Not implemented; recording uses a ten-minute interval | Requires implementation |
| Playback speed 2x/4x/8x | Not implemented | Requires implementation |
| Clip export and confirmed WhatsApp sharing | Not implemented | Requires implementation |

These unfinished items remain in scope; generating an APK does not complete them.

## First phone test

1. Download and unzip the `zvektra-android-debug-apk` Actions artifact. Install
   `app-debug.apk` on Android 6 or later. This is a debug-signed test build.
2. Open Devices and add the NVR's name, manufacturer, actual forwarded port,
   channel limit, username and password. No device credentials belong in GitHub.
3. Relaunch and check that the device and its saved password remain usable.
4. On a reachable Dahua NVR, test camera 3 live with sound, then a known recording
   through the date/time picker. Test pause, resume, and +/-30 seconds.
5. Switch cameras repeatedly and verify that the picture actually changes.
6. Test microphone permission denied and allowed. Confirm transcription remains
   editable and does not execute until requested. Test text commands separately.
7. Record phone model, Android version, NVR model and firmware, requested camera,
   observed result and error text. Do not share passwords or full RTSP URLs.

The build checks URL escaping and playback interval construction, and rejects
unimplemented vendor playback paths. It does not test network reachability,
decoding, credential persistence, microphone services or actual NVR behavior.
