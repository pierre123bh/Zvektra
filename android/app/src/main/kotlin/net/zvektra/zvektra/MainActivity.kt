package net.zvektra.zvektra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var detection: PlaybackDetectionChannel? = null
    private var voiceClip: VoiceClipRecorder? = null
    private var speechVoice: AndroidSpeechVoice? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        detection = PlaybackDetectionChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        voiceClip = VoiceClipRecorder(this, flutterEngine.dartExecutor.binaryMessenger)
        speechVoice = AndroidSpeechVoice(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        detection?.close()
        detection = null
        voiceClip?.close()
        voiceClip = null
        speechVoice?.close()
        speechVoice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        voiceClip?.cancel()
        speechVoice?.cancel()
        super.onStop()
    }
}
