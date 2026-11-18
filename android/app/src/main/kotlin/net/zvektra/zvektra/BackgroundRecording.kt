package net.zvektra.zvektra

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

internal class BackgroundRecording(
    private val context: Context,
    private val cancelled: () -> Boolean,
    private val progress: (String, Int) -> Unit,
) {
    data class Result(val saved: Int, val partial: Boolean)
    private var saved = 0

    fun run(sources: List<String>, start: Long, length: Long, camera: Int, timezone: String): Result {
        val input = try {
            File.createTempFile("background-recording-", ".mp4", context.cacheDir)
        } catch (_: IOException) {
            return Result(0, true)
        }
        try {
            var duration = 0L
            for (source in sources) {
                require(Uri.parse(source).let { it.scheme == "rtsp" && !it.host.isNullOrEmpty() })
                for (videoOnly in listOf(false, true)) {
                    if (cancelled()) return Result(saved, true)
                    input.delete()
                    capture(Uri.parse(source), input, length, videoOnly)
                    duration = videoDuration(input)
                    if (duration >= 400) break
                }
                if (duration >= 400) break
            }
            if (cancelled() || duration < 400) return Result(saved, true)

            val available = minOf(duration, length)
            val retriever = MediaMetadataRetriever()
            val lastSeen = mutableMapOf<String, Long>()
            val events = mutableListOf<Pair<String, Long>>()
            var missingFrames = false
            try {
                retriever.setDataSource(input.absolutePath)
                PlaybackDetector(context).use { detector ->
                    var offset = 0L
                    while (offset < available && !cancelled()) {
                        progress("Analyzing recording", 45 + (offset * 40 / available).toInt())
                        val frame = retriever.getFrameAtTime(offset * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
                        if (frame == null) {
                            missingFrames = true
                        } else {
                            try {
                                for (kind in detector.detectKinds(frame)) {
                                    if (offset - (lastSeen[kind] ?: -4000L) > 3000) events.add(kind to offset)
                                    lastSeen[kind] = offset
                                }
                            } finally {
                                frame.recycle()
                            }
                        }
                        offset += 1000
                    }
                }
            } finally {
                retriever.release()
            }

            val formatter = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US).apply {
                timeZone = TimeZone.getTimeZone(timezone)
            }
            var failed = false
            for ((index, event) in events.withIndex()) {
                if (cancelled()) break
                progress("Saving clips ($saved of " + events.size + ")", 85 + index * 14 / events.size)
                val (kind, offset) = event
                val date = formatter.format(Date(start + offset))
                val label = if (kind == "person") "Person" else "Vehicle"
                val filename = "Zvektra-$date-Cam$camera-$label.mp4"
                try {
                    saveClip(input, filename, maxOf(0, offset - 5000), minOf(available, offset + 10000))
                    saved++
                } catch (_: Exception) {
                    failed = true
                }
            }
            return Result(saved, cancelled() || duration + 2000 < length || missingFrames || failed)
        } catch (_: Exception) {
            return Result(saved, true)
        } catch (_: LinkageError) {
            return Result(saved, true)
        } finally {
            input.delete()
        }
    }

    private fun capture(source: Uri, file: File, length: Long, videoOnly: Boolean) {
        val vlc = LibVLC(context, arrayListOf("--rtsp-tcp", "--network-caching=1000"))
        try {
            val player = MediaPlayer(vlc)
            try {
                val done = CountDownLatch(1)
                val position = AtomicLong(0)
                val media = Media(vlc, source)
                try {
                    media.addOption(":sout=#std{access=file,mux=mp4,dst=" + file.absolutePath + "}")
                    media.addOption(":stop-time=" + ((length + 999) / 1000))
                    if (videoOnly) media.addOption(":no-sout-audio")
                    player.media = media
                } finally {
                    media.release()
                }
                player.setEventListener { event ->
                    when (event.type) {
                        MediaPlayer.Event.EndReached, MediaPlayer.Event.EncounteredError -> done.countDown()
                        MediaPlayer.Event.TimeChanged -> position.set(event.timeChanged)
                    }
                    Unit
                }
                player.play()
                var lastBytes = 0L
                var idleSeconds = 0
                while (!cancelled() && !done.await(1, TimeUnit.SECONDS)) {
                    val bytes = file.length()
                    idleSeconds = if (bytes > lastBytes) 0 else idleSeconds + 1
                    lastBytes = bytes
                    val elapsed = position.get()
                    if (elapsed >= length || idleSeconds >= 25 || context.cacheDir.usableSpace < 64L * 1024 * 1024) break
                    progress("Reading recording", (elapsed.coerceIn(0, length) * 45 / length).toInt())
                }
            } finally {
                runCatching { player.setEventListener(null) }
                runCatching { player.stop() }
                player.release()
            }
        } finally {
            vlc.release()
        }
    }

    private fun saveClip(input: File, filename: String, start: Long, end: Long) {
        val output = File.createTempFile("background-clip-", ".mp4", context.cacheDir)
        try {
            muxVideo(input, output, start * 1000, end * 1000)
            if (cancelled()) throw IOException("Analysis stopped")
            if (videoDuration(output) < 400) throw IOException("Empty clip")
            if (Build.VERSION.SDK_INT >= 29) {
                publishModernClip(context, output, filename)
            } else {
                saveLegacyClip(output, filename)
            }
        } finally {
            output.delete()
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacyClip(file: File, filename: String) {
        val album = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Zvektra")
        if (!album.isDirectory && !album.mkdirs()) throw IOException("Could not create album")
        val destination = File(album, filename)
        if (destination.exists()) return
        try {
            file.copyTo(destination)
            MediaScannerConnection.scanFile(context, arrayOf(destination.absolutePath), arrayOf("video/mp4"), null)
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    private fun muxVideo(input: File, output: File, startUs: Long, endUs: Long) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(input.absolutePath)
            val track = (0 until extractor.trackCount).first { index ->
                extractor.getTrackFormat(index).getString("mime")?.startsWith("video/") == true
            }
            extractor.selectTrack(track)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val origin = extractor.sampleTime
            if (origin < 0 || origin >= endUs) throw IOException("No keyframe")
            val format = extractor.getTrackFormat(track)
            val capacity = if (format.containsKey("max-input-size")) format.getInteger("max-input-size") else 0
            val buffer = ByteBuffer.allocateDirect(maxOf(capacity, 4 * 1024 * 1024))
            val info = android.media.MediaCodec.BufferInfo()
            val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val outputTrack = muxer.addTrack(format)
                muxer.start()
                while (!cancelled()) {
                    val time = extractor.sampleTime
                    if (time < 0 || time >= endUs) break
                    buffer.clear()
                    val size = extractor.readSampleData(buffer, 0)
                    if (size <= 0) break
                    info.set(0, size, time - origin, extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC)
                    muxer.writeSampleData(outputTrack, buffer, info)
                    extractor.advance()
                }
                muxer.stop()
            } finally {
                muxer.release()
            }
        } finally {
            extractor.release()
        }
    }
}
