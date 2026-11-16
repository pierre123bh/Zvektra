package net.zvektra.zvektra

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val whatsappPackages = listOf("com.whatsapp", "com.whatsapp.w4b")
    private var snapshotShare: MethodChannel? = null
    private var detection: PlaybackDetectionChannel? = null
    private var speechVoice: AndroidSpeechVoice? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        snapshotShare = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "net.zvektra/snapshot_share")
        snapshotShare?.setMethodCallHandler { call, result ->
            val jpeg = call.arguments as? ByteArray
            when {
                call.method == "available" -> result.success(whatsappPackages.any { target ->
                    Intent(Intent.ACTION_SEND).setType("image/jpeg").setPackage(target)
                        .resolveActivity(packageManager) != null
                })
                call.method != "whatsapp" -> result.notImplemented()
                jpeg == null || jpeg.isEmpty() -> result.error("INVALID_IMAGE", null, null)
                else -> try {
                    if (shareWhatsApp(jpeg)) result.success(null)
                    else result.error("WHATSAPP_UNAVAILABLE", null, null)
                } catch (_: Exception) {
                    result.error("SHARE_FAILED", null, null)
                }
            }
        }
        detection = PlaybackDetectionChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        speechVoice = AndroidSpeechVoice(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        snapshotShare?.setMethodCallHandler(null)
        snapshotShare = null
        detection?.close()
        detection = null
        speechVoice?.close()
        speechVoice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun shareWhatsApp(jpeg: ByteArray): Boolean {
        val directory = File(cacheDir, "shared-snapshots").apply { mkdirs() }
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        directory.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
        val snapshot = File.createTempFile("zvektra-", ".jpg", directory)
        var sharedFileInUse = false
        try {
            snapshot.writeBytes(jpeg)
            val uri = FileProvider.getUriForFile(this, "$packageName.snapshots", snapshot)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/jpeg"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri("Zvektra snapshot", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            for (target in whatsappPackages) {
                try {
                    startActivity(intent.setPackage(target))
                    sharedFileInUse = true
                    return true
                } catch (_: ActivityNotFoundException) {
                    // Try the other WhatsApp edition.
                }
            }
            return false
        } finally {
            // Keep successful shares available while WhatsApp's composer is open.
            if (!sharedFileInUse) snapshot.delete()
        }
    }

    override fun onStop() {
        speechVoice?.cancel()
        super.onStop()
    }
}
