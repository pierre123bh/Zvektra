# Offline Whisper preview

This build installs as **Zvektra Whisper** alongside the working Zvektra 0.1.5 app. Device settings are stored separately in the preview.

Tap the microphone to record, then tap it again to stop. A recording also stops automatically after ten seconds. The app uses Whisper's bundled multilingual Tiny model to transcribe on the phone. Speech audio stays in memory during processing. The result stays in the editable command box until you choose an action.

The existing command parser still interprets English commands, for example “show camera three.” Whisper can transcribe other languages. Interpreting French or Arabic commands is separate work.

Gradle fetches the checksum-verified model when building. The APK contains the model and needs no first-run download.
