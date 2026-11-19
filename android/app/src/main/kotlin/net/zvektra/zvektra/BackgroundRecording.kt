package net.zvektra.zvektra

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.SystemClock
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Stored JPEG archives only. There is deliberately no video or live snapshot fallback. */
internal class BackgroundRecording(
    private val context: Context,
    private val cancelled: () -> Boolean,
    private val progress: (String, Int) -> Unit,
) {
    data class Result(val saved: Int, val partial: Boolean, val details: String? = null, val images: Boolean = true)

    fun run(sources: List<String>, start: Long, length: Long, camera: Int, timezone: String,
            downloadPort: Int? = null, recorderFamily: String = "Dahua", deviceName: String = "Recorder"): Result {
        if (downloadPort == null) return Result(0, true,
            "Set Zvektra Port 2 to the recorder's archive API port. No video fallback was attempted.")
        val source = sources.firstOrNull()?.let(Uri::parse)
        val host = source?.host
        val credentials = source?.encodedUserInfo?.split(':', limit = 2)
        if (host == null || credentials?.size != 2) return Result(0, true, "Invalid snapshot archive address or login.")
        val began = SystemClock.elapsedRealtime()
        var found = 0
        var saved = 0
        var duplicates = 0
        var excluded = 0
        var cachedBytes = 0L
        var lastTime = Long.MIN_VALUE
        var lastSignature: IntArray? = null
        var lastKinds: Set<String>? = null
        val reportImages = mutableListOf<Pair<Long, File>>()
        val formatter = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone(timezone)
        }
        var error: String? = null
        try {
            PlaybackDetector(context).use { detector ->
                val consume: (Long, ByteArray) -> Boolean = consume@ { timestamp, jpeg ->
                    if (cancelled()) return@consume false
                    if (timestamp < start || timestamp >= start + length) throw IOException("Snapshot timestamp outside the requested range")
                    if (jpeg.size !in 4..16 * 1024 * 1024 || jpeg[0] != 0xff.toByte() || jpeg[1] != 0xd8.toByte())
                        throw IOException("The archive returned non-JPEG data; no video was processed")
                    found++
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
                    if (bounds.outWidth < 1 || bounds.outHeight < 1 || bounds.outWidth.toLong() * bounds.outHeight > 100_000_000)
                        throw IOException("Invalid or oversized snapshot dimensions")
                    val options = BitmapFactory.Options().apply { inSampleSize = 1 }
                    while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize.coerceAtLeast(1) > 1280) {
                        options.inSampleSize = options.inSampleSize.coerceAtLeast(1) * 2
                    }
                    val frame = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, options)
                        ?: throw IOException("Stored snapshot could not be decoded")
                    try {
                        val kinds = detector.snapshotKinds(frame)
                        if (kinds.isEmpty()) excluded++ else {
                            val signature = signature(frame)
                            val previous = lastSignature
                            val closeInTime = lastTime != Long.MIN_VALUE && timestamp >= lastTime && timestamp - lastTime <= 30_000
                            val similar = previous != null && closeInTime && lastKinds == kinds && similar(previous, signature)
                            if (similar) duplicates++ else {
                                val label = kinds.sorted().joinToString("-")
                                val filename = "Zvektra-${formatter.format(Date(timestamp))}-Cam$camera-$label-$found.jpg"
                                if (context.cacheDir.usableSpace < jpeg.size + 64L * 1024 * 1024 ||
                                    cachedBytes + jpeg.size > 512L * 1024 * 1024)
                                    throw IOException("Snapshot report storage limit reached; use a shorter range")
                                val cached = File.createTempFile("background-image-", ".jpg", context.cacheDir)
                                try {
                                    cached.writeBytes(jpeg)
                                    publishSnapshot(context, filename, jpeg)
                                    reportImages.add(timestamp to cached)
                                    cachedBytes += jpeg.size
                                } catch (failure: Exception) { cached.delete(); throw failure }
                                saved++
                                lastSignature = signature
                                lastKinds = kinds
                            }
                            lastTime = timestamp
                        }
                    } finally { frame.recycle() }
                    progress("Stored snapshots: $found received · $saved saved · $duplicates similar skipped", 50)
                    !cancelled()
                }
                progress("Searching stored JPEG snapshots", 0)
                val user = Uri.decode(credentials[0])
                val pass = Uri.decode(credentials[1])
                when (recorderFamily) {
                    "Dahua" -> DahuaNativeDownload.snapshots(host, downloadPort, user, pass, camera,
                        start, start + length, timezone, context.cacheDir, cancelled, consume)
                    "Dahua HTTP", "Hikvision" -> StoredSnapshotHttp(host, downloadPort, user, pass, cancelled)
                        .search(recorderFamily, camera, start, start + length, timezone, consume)
                    "MEye", "Xiongmai", "Topcam" -> XiongmaiArchive(host, downloadPort, user, pass, cancelled)
                        .snapshots(camera, start, start + length, timezone, consume)
                    else -> throw IOException("Stored snapshot archive search is not implemented for $recorderFamily. No video or live snapshots were requested.")
                }
            }
        } catch (failure: Exception) {
            error = failure.message ?: failure.javaClass.simpleName
        } catch (failure: LinkageError) {
            error = "Snapshot SDK unavailable: ${failure.javaClass.simpleName}"
        }
        var pdf = ""
        try {
            if (saved > 0 && !cancelled()) {
                progress("Creating snapshot PDF", 95)
                val parts = reportImages.chunked(50)
                for ((index, images) in parts.withIndex()) {
                    SnapshotReport.save(context, deviceName, camera, start, start + length, timezone, images,
                        error != null, cancelled, index + 1, parts.size)
                }
                pdf = " ${parts.size} PDF report(s) saved in Downloads/Zvektra."
            }
        } catch (_: Exception) { error = listOfNotNull(error, "Images saved, but PDF export failed").joinToString(". ") }
        finally { reportImages.forEach { it.second.delete() } }
        val detail = when {
            error != null -> "Snapshot search incomplete: $error."
            cancelled() -> "Snapshot search stopped."
            found == 0 -> "No snapshots detected for that date and time."
            saved == 0 -> "Stored snapshots were found, but no people or vehicles were detected."
            else -> "$saved representative people/vehicle snapshots saved."
        }
        return Result(saved, error != null || cancelled(),
            "$detail $found JPEGs received, $duplicates similar images skipped, $excluded without people/vehicles. " +
            "Total ${String.format(Locale.US, "%.1f", (SystemClock.elapsedRealtime() - began) / 1000.0)}s.$pdf")
    }

    private fun signature(frame: Bitmap): IntArray {
        val small = Bitmap.createScaledBitmap(frame, 160, 90, true)
        try {
            val pixels = IntArray(160 * 90)
            small.getPixels(pixels, 0, 160, 0, 0, 160, 90)
            return pixels.map { (((it shr 16) and 255) * 77 + ((it shr 8) and 255) * 150 + (it and 255) * 29) shr 8 }.toIntArray()
        } finally { if (small !== frame) small.recycle() }
    }

    private fun similar(left: IntArray, right: IntArray): Boolean {
        var total = 0L
        var changed = 0
        for (i in left.indices) {
            val difference = kotlin.math.abs(left[i] - right[i])
            total += difference
            if (difference > 15) changed++
        }
        return total < left.size * 2L && changed < left.size / 200
    }
}
