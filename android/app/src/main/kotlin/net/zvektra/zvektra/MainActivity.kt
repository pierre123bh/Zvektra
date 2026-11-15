package net.zvektra.zvektra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var whisperVoice: WhisperVoice? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        whisperVoice = WhisperVoice(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        whisperVoice?.close()
        whisperVoice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        whisperVoice?.cancel()
        super.onStop()
    }
}
