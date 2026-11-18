package net.zvektra.zvektra

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.IOException
import java.util.UUID

internal class SnapshotGalleryChannel(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val channel = MethodChannel(
        messenger, "net.zvektra/snapshot_gallery", StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requiresStoragePermission" -> result.success(Build.VERSION.SDK_INT < 29)
                "save" -> {
                    val jpeg = call.arguments as? ByteArray
                    if (jpeg == null || jpeg.isEmpty()) {
                        result.error("INVALID_IMAGE", null, null)
                    } else {
                        try {
                            val name = "Zvektra-${UUID.randomUUID()}.jpg"
                            if (Build.VERSION.SDK_INT >= 29) {
                                publishSnapshot(app, name, jpeg)
                                result.success(null)
                            } else {
                                saveLegacy(name, jpeg, result)
                            }
                        } catch (_: Exception) {
                            result.error("SAVE_FAILED", null, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(name: String, jpeg: ByteArray, result: MethodChannel.Result) {
        val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val album = File(pictures, "Zvektra")
        if (!album.isDirectory && !album.mkdirs()) throw IOException("Could not create album")
        val file = File(album, name)
        try {
            file.writeBytes(jpeg)
            MediaScannerConnection.scanFile(app, arrayOf(file.absolutePath), arrayOf("image/jpeg")) { _, uri ->
                if (uri == null) {
                    file.delete()
                    result.error("SAVE_FAILED", null, null)
                } else {
                    result.success(null)
                }
            }
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
    }
}

internal fun publishSnapshot(app: Context, name: String, jpeg: ByteArray) {
        if (Build.VERSION.SDK_INT < 29) {
            @Suppress("DEPRECATION")
            val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Zvektra")
            if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Could not create image album")
            val file = File(folder, name)
            try {
                file.writeBytes(jpeg)
                MediaScannerConnection.scanFile(app, arrayOf(file.absolutePath), arrayOf("image/jpeg"), null)
            } catch (error: Exception) {
                file.delete()
                throw error
            }
            return
        }
        val resolver = app.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Zvektra")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not create gallery entry")
        try {
            val stream = resolver.openOutputStream(uri)
                ?: throw IOException("Could not open gallery entry")
            stream.use { it.write(jpeg) }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            if (resolver.update(uri, values, null, null) != 1) {
                throw IOException("Could not publish gallery entry")
            }
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }
