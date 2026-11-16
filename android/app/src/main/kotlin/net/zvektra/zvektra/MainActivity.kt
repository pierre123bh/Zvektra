package net.zvektra.zvektra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var snapshotGallery: SnapshotGalleryChannel? = null
    private var detection: PlaybackDetectionChannel? = null
    private var speechVoice: AndroidSpeechVoice? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        snapshotGallery = SnapshotGalleryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        detection = PlaybackDetectionChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        speechVoice = AndroidSpeechVoice(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        snapshotGallery?.close()
        snapshotGallery = null
        detection?.close()
        detection = null
        speechVoice?.close()
        speechVoice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        speechVoice?.cancel()
        super.onStop()
    }
}
