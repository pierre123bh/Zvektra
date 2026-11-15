package net.zvektra.zvektra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var speechVoice: AndroidSpeechVoice? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speechVoice = AndroidSpeechVoice(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        speechVoice?.close()
        speechVoice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        speechVoice?.cancel()
        super.onStop()
    }
}
