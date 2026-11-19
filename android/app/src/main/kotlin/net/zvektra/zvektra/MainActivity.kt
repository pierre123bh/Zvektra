package net.zvektra.zvektra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var backgroundAgent: MethodChannel? = null
    private var clipGallery: ClipGalleryChannel? = null
    private var snapshotGallery: SnapshotGalleryChannel? = null
    private var detection: PlaybackDetectionChannel? = null
    private var speechVoice: AndroidSpeechVoice? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backgroundAgent = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.zvektra/background_agent")
        backgroundAgent?.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(BackgroundAgentService.status(this))
                "start" -> {
                    val sources = call.argument<List<String>>("sources").orEmpty()
                    val start = call.argument<Number>("start")?.toLong() ?: 0L
                    val end = call.argument<Number>("end")?.toLong() ?: 0L
                    val camera = call.argument<Int>("camera") ?: 0
                    val deviceName = call.argument<String>("deviceName") ?: "Recorder"
                    val recorderFamily = call.argument<String>("recorderFamily") ?: "Dahua"
                    val downloadPort = call.argument<Int>("downloadPort")?.takeIf { it in 1..65535 }
                    if (sources.isEmpty() || start <= 0 || end <= start || camera <= 0) {
                        result.error("INVALID_RANGE", null, null)
                    } else {
                        try {
                            result.success(BackgroundAgentService.start(applicationContext,
                                ArrayList(sources), start, end, camera, TimeZone.getDefault().id, downloadPort, recorderFamily, deviceName))
                        } catch (_: RuntimeException) {
                            result.error("BACKGROUND_START_FAILED", null, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        clipGallery = ClipGalleryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        snapshotGallery = SnapshotGalleryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        detection = PlaybackDetectionChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        speechVoice = AndroidSpeechVoice(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backgroundAgent?.setMethodCallHandler(null)
        backgroundAgent = null
        clipGallery?.close()
        clipGallery = null
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
