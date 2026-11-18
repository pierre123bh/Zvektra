package net.zvektra.zvektra

import android.content.ContentValues
import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import java.io.File
import java.io.IOException
import java.util.UUID

internal class ClipGalleryChannel(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val channel = MethodChannel(messenger, "net.zvektra/clip_gallery")
    private val thread = HandlerThread("zvektra-clip-export").apply { start() }
    private val worker = Handler(thread.looper)
    private var job: Export? = null

    private class Export(
        val result: MethodChannel.Result,
        val file: File,
        val seconds: Int,
    ) {
        var vlc: LibVLC? = null
        var player: MediaPlayer? = null
        var timeout: Runnable? = null
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "save") {
                result.notImplemented()
            } else {
                val source = call.argument<String>("source")?.let(Uri::parse)
                val seconds = call.argument<Int>("seconds")
                if (source?.scheme != "rtsp" || source.host.isNullOrEmpty() ||
                    seconds == null || seconds !in 1..15) {
                    result.error("INVALID_CLIP", null, null)
                } else {
                    val videoOnly = call.argument<Boolean>("videoOnly") == true
                    worker.post { start(source, seconds, videoOnly, result) }
                }
            }
        }
    }

    private fun start(source: Uri, seconds: Int, videoOnly: Boolean, result: MethodChannel.Result) {
        if (job != null) {
            result.error("BUSY", null, null)
            return
        }
        val name = "Zvektra-${UUID.randomUUID()}.mp4"
        val export = Export(result, File(app.cacheDir, name), seconds)
        job = export
        try {
            val vlc = LibVLC(app, arrayListOf("--rtsp-tcp", "--network-caching=1000"))
            export.vlc = vlc
            val player = MediaPlayer(vlc)
            export.player = player
            val media = Media(vlc, source)
            try {
                media.addOption(":sout=#std{access=file,mux=mp4,dst=${export.file.absolutePath}}")
                media.addOption(":stop-time=$seconds")
                if (videoOnly) media.addOption(":no-sout-audio")
                player.media = media
            } finally {
                media.release()
            }
            player.setEventListener { event ->
                when (event.type) {
                    MediaPlayer.Event.EndReached -> worker.post { finish(export, true) }
                    MediaPlayer.Event.EncounteredError -> worker.post { finish(export, true) }
                    MediaPlayer.Event.TimeChanged -> if (event.timeChanged >= seconds * 1000L) {
                        worker.post { finish(export, true) }
                    }
                }
                Unit
            }
            export.timeout = Runnable { finish(export, true) }.also {
                worker.postDelayed(it, (seconds + 25) * 1000L)
            }
            player.play()
        } catch (_: Exception) {
            finish(export, false)
        }
    }

    private fun finish(export: Export, keepVideo: Boolean) {
        if (job !== export) return
        job = null
        export.timeout?.let(worker::removeCallbacks)
        export.player?.let { player ->
            runCatching { player.setEventListener(null) }
            runCatching { player.stop() }
            runCatching { player.release() }
        }
        runCatching { export.vlc?.release() }
        try {
            val duration = if (keepVideo) videoDuration(export.file) else 0L
            if (duration !in 400L..((export.seconds + 2) * 1000L)) {
                export.result.error("NO_PLAYABLE_CLIP", null, null)
                return
            }
            val shortened = duration < (export.seconds - 2) * 1000L
            if (Build.VERSION.SDK_INT >= 29) {
                publishModernClip(app, export.file)
                export.result.success(shortened)
            } else {
                saveLegacy(export.file, shortened, export.result)
            }
        } catch (_: Exception) {
            export.result.error("CLIP_EXPORT_FAILED", null, null)
        } finally {
            export.file.delete()
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(file: File, shortened: Boolean, result: MethodChannel.Result) {
        val movies = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        val album = File(movies, "Zvektra")
        if (!album.isDirectory && !album.mkdirs()) throw IOException("Could not create album")
        val destination = File(album, file.name)
        try {
            file.copyTo(destination)
            MediaScannerConnection.scanFile(app, arrayOf(destination.absolutePath), arrayOf("video/mp4")) { _, uri ->
                if (uri == null) {
                    destination.delete()
                    result.error("CLIP_EXPORT_FAILED", null, null)
                } else {
                    result.success(shortened)
                }
            }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.post {
            job?.let { finish(it, false) }
            thread.quitSafely()
        }
    }
}

internal fun videoDuration(file: File): Long {
    if (file.length() == 0L) return 0
    val metadata = MediaMetadataRetriever()
    return try {
        metadata.setDataSource(file.absolutePath)
        val duration = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLongOrNull() ?: 0
        if (metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes") duration else 0L
    } catch (_: Exception) {
        0L
    } finally {
        metadata.release()
    }
}

@androidx.annotation.RequiresApi(29)
internal fun publishModernClip(context: Context, file: File, name: String = file.name) {
    val resolver = context.contentResolver
    val values = ContentValues().apply {
        put(MediaStore.Video.Media.DISPLAY_NAME, name)
        put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
        put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/Zvektra")
        put(MediaStore.Video.Media.IS_PENDING, 1)
    }
    val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
        ?: throw IOException("Could not create gallery entry")
    try {
        val stream = resolver.openOutputStream(uri) ?: throw IOException("Could not open video")
        stream.use { output -> file.inputStream().use { it.copyTo(output) } }
        values.clear()
        values.put(MediaStore.Video.Media.IS_PENDING, 0)
        if (resolver.update(uri, values, null, null) != 1) throw IOException("Could not publish video")
    } catch (error: Exception) {
        runCatching { resolver.delete(uri, null, null) }
        throw error
    }
}
