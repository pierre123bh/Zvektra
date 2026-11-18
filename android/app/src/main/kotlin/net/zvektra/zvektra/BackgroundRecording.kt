package net.zvektra.zvektra

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.util.Log
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
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

internal class BackgroundRecording(
    private val context: Context,
    private val cancelled: () -> Boolean,
    private val progress: (String, Int) -> Unit,
) {
    data class Result(val saved: Int, val partial: Boolean, val details: String? = null)
    private var saved = 0

    fun run(sources: List<String>, start: Long, length: Long, camera: Int, timezone: String,
            downloadPort: Int? = null, recorderFamily: String = "Dahua"): Result {
        val input = try {
            File.createTempFile("background-recording-", ".mp4", context.cacheDir)
        } catch (_: IOException) {
            return Result(0, true)
        }
        val jobStarted = SystemClock.elapsedRealtime()
        var stage = "opening the recording"
        try {
            val supportsDownload = recorderFamily == "Dahua" || recorderFamily == "Hikvision"
            var duration = if (downloadPort == null || !supportsDownload) 0L else
                tryDownload(Uri.parse(sources.first()), downloadPort, input, start, length, camera, timezone, recorderFamily)
            var route = "Zvektra Port 2"
            val fallback = if (downloadPort != null && !supportsDownload) {
                " Zvektra Port 2 download is unavailable for this device."
            } else if (downloadPort != null && !coversRange(duration, length)) {
                " Zvektra Port 2 supplied ${seconds(duration)} before fallback."
            } else ""
            if (!coversRange(duration, length) && !cancelled()) {
                progress("Reading recording through Zvektra Port 1", 0)
                val rtsp = File.createTempFile("background-recording-", ".mp4", context.cacheDir)
                try {
                    val rtspDuration = capturePlayback(sources, rtsp, length)
                    if (rtspDuration > duration && rtsp.renameTo(input)) {
                        duration = rtspDuration
                        route = "Zvektra Port 1"
                    }
                } finally {
                    rtsp.delete()
                }
            }
            if (cancelled() || duration < 400) return Result(saved, true,
                "No playable recording. Read ${seconds(SystemClock.elapsedRealtime() - jobStarted)}.$fallback")

            val acquisitionMs = SystemClock.elapsedRealtime() - jobStarted
            stage = "scanning frames"
            val analysisStarted = SystemClock.elapsedRealtime()
            val available = minOf(duration, length)
            val retriever = MediaMetadataRetriever()
            val lastSeen = mutableMapOf<String, Long>()
            val events = mutableListOf<Pair<String, Long>>()
            val plateWorker = Executors.newSingleThreadExecutor()
            val syncFrames = MediaExtractor()
            var missingFrames = 0
            try {
                retriever.setDataSource(input.absolutePath)
                val seekable = runCatching {
                    syncFrames.setDataSource(input.absolutePath)
                    val track = (0 until syncFrames.trackCount).first { index ->
                        syncFrames.getTrackFormat(index).getString("mime")?.startsWith("video/") == true
                    }
                    syncFrames.selectTrack(track)
                    true
                }.getOrDefault(false)
                val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                val largestSide = maxOf(width, height)
                val scale = if (largestSide > 960) 960.0 / largestSide else 1.0
                PlaybackDetector(context).use { detector ->
                    var offset = 0L
                    while (offset < available && !cancelled()) {
                        progress("Analyzing recording", 45 + (offset * 40 / available).toInt())
                        val timeUs = offset * 1000
                        val option = if (seekable && runCatching {
                                syncFrames.seekTo(timeUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                                val syncTime = syncFrames.sampleTime
                                syncTime >= 0 && kotlin.math.abs(syncTime - timeUs) <= 100_000L
                            }.getOrDefault(false)) MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                            else MediaMetadataRetriever.OPTION_CLOSEST
                        val scaled = if (Build.VERSION.SDK_INT >= 27 && scale < 1.0 && width > 0 && height > 0) {
                            runCatching { retriever.getScaledFrameAtTime(timeUs, option,
                                (width * scale).toInt().coerceAtLeast(1),
                                (height * scale).toInt().coerceAtLeast(1)) }.getOrNull()
                        } else null
                        val frame = scaled ?: retriever.getFrameAtTime(timeUs, option)
                        if (frame == null) {
                            missingFrames++
                        } else {
                            try {
                                for (kind in detector.detectKinds(frame, plateWorker)) {
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
                plateWorker.shutdown()
                syncFrames.release()
                retriever.release()
            }

            val analysisMs = SystemClock.elapsedRealtime() - analysisStarted
            stage = "saving clips"
            val savingStarted = SystemClock.elapsedRealtime()
            val formatter = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US).apply {
                timeZone = TimeZone.getTimeZone(timezone)
            }
            var failed = 0
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
                    failed++
                }
            }
            val savingMs = SystemClock.elapsedRealtime() - savingStarted
            val total = SystemClock.elapsedRealtime() - jobStarted
            val issues = buildList {
                if (!coversRange(duration, length)) add("Footage ${seconds(available)} of ${seconds(length)}.")
                if (missingFrames > 0) add("$missingFrames frames could not be decoded.")
                if (failed > 0) add("$failed clips could not be saved.")
            }
            val issueText = issues.joinToString(" ", prefix = if (issues.isEmpty()) "" else " ")
            val details = "$route. Read ${seconds(acquisitionMs)} · Scan ${seconds(analysisMs)} · Save ${seconds(savingMs)} · Total ${seconds(total)}.$fallback$issueText"
            Log.i("BackgroundAgent", "Recording=$length ms. $details")
            return Result(saved, cancelled() || issues.isNotEmpty(), details)
        } catch (error: Exception) {
            return Result(saved, true, "Stopped while $stage (${error.javaClass.simpleName}).")
        } catch (error: LinkageError) {
            return Result(saved, true, "Stopped while $stage (${error.javaClass.simpleName}).")
        } finally {
            input.delete()
        }
    }

    private fun seconds(milliseconds: Long) = String.format(Locale.US, "%.1fs", milliseconds / 1000.0)

    private fun coversRange(duration: Long, length: Long) =
        duration >= 400 && length - duration <= minOf(2000L, length / 10)

    private fun capturePlayback(sources: List<String>, input: File, length: Long): Long {
        var best = 0L
        val attempt = File.createTempFile("background-recording-", ".mp4", context.cacheDir)
        try {
            for (source in sources) {
                val uri = Uri.parse(source)
                require(uri.scheme == "rtsp" && !uri.host.isNullOrEmpty())
                for (videoOnly in listOf(true, false)) {
                    if (cancelled()) return best
                    attempt.delete()
                    capture(uri, attempt, length, videoOnly)
                    val duration = videoDuration(attempt)
                    if (duration > best && attempt.renameTo(input)) best = duration
                    if (coversRange(best, length)) return best
                    // A working video track with short coverage will not gain
                    // duration by including audio. Try the next recorder URL.
                    if (duration >= 400) break
                }
            }
            return best
        } finally {
            attempt.delete()
        }
    }

    private fun tryDownload(source: Uri, outputPort: Int, output: File, start: Long, length: Long,
                            camera: Int, timezone: String, recorderFamily: String): Long {
        val raw = File.createTempFile("background-recording-", ".dav", context.cacheDir)
        // The target is end-to-end wall time, not a deadline for discarding
        // usable footage and paying for a second acquisition at RTSP speed.
        val budgetMs = (length / 2).coerceAtLeast(4000L)
        val deadline = SystemClock.elapsedRealtime() + budgetMs
        val stopFastPath = { cancelled() || SystemClock.elapsedRealtime() >= deadline }
        try {
            progress("Downloading recording through Zvektra Port 2", 0)
            if (!RecorderRecordingDownload.save(source, outputPort, camera, start, length, timezone, recorderFamily, raw, stopFastPath)) return 0L
            if (cancelled()) return 0L
            val signature = raw.inputStream().use { stream ->
                ByteArray(5).also { stream.read(it) }.toString(Charsets.US_ASCII)
            }
            val dahua = signature.startsWith("DHAV") || signature == "DAHUA"
            val readable = if (dahua) 0L else videoDuration(raw)
            if (readable >= 400) {
                output.delete()
                if (!raw.renameTo(output)) return 0L
                return readable
            } else {
                output.delete()
                progress("Preparing Zvektra Port 2 recording", 30)
                capture(Uri.fromFile(raw), output, length, videoOnly = true,
                    local = true, dav = dahua, stop = stopFastPath)
                if (cancelled()) return 0L
            }
            return videoDuration(output)
        } catch (_: Exception) {
            return 0L
        } finally {
            raw.delete()
            if (!cancelled() && stopFastPath()) {
                Log.i("BackgroundAgent", "Port 2 exceeded its $budgetMs ms acquisition budget")
            }
        }
    }

    private fun capture(source: Uri, file: File, length: Long, videoOnly: Boolean,
                        local: Boolean = false, dav: Boolean = false, stop: () -> Boolean = cancelled) {
        val vlc = LibVLC(context, arrayListOf("--rtsp-tcp", "--network-caching=1000"))
        try {
            val player = MediaPlayer(vlc)
            try {
                val done = CountDownLatch(1)
                val position = AtomicLong(0)
                val media = Media(vlc, source)
                try {
                    media.addOption(":sout=#std{access=file,mux=mp4,dst=" + file.absolutePath + "}")
                    if (!local) media.addOption(":stop-time=" + ((length + 999) / 1000))
                    if (dav) {
                        media.addOption(":demux=avformat")
                        media.addOption(":avformat-format=dhav")
                    }
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
                val captureStarted = SystemClock.elapsedRealtime()
                var lastGrowth = captureStarted
                while (!stop() && !done.await(if (local) 100 else 1000, TimeUnit.MILLISECONDS)) {
                    val bytes = file.length()
                    if (bytes > lastBytes) lastGrowth = SystemClock.elapsedRealtime()
                    lastBytes = bytes
                    val elapsed = position.get()
                    val now = SystemClock.elapsedRealtime()
                    val idleLimit = if (bytes == 0L && !local) 8000L else 15000L
                    if ((!local && now - captureStarted >= length + 15000L) ||
                        now - lastGrowth >= idleLimit || context.cacheDir.usableSpace < 64L * 1024 * 1024) break
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
