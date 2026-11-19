package net.zvektra.zvektra

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object SnapshotReport {
    fun save(context: Context, deviceName: String, camera: Int, start: Long, end: Long, timezone: String,
             images: List<Pair<Long, File>>, partial: Boolean, cancelled: () -> Boolean, part: Int, totalParts: Int) {
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply { timeZone = TimeZone.getTimeZone(timezone) }
        val nameTime = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).apply { timeZone = TimeZone.getTimeZone(timezone) }
        val name = "Zvektra-Cam$camera-${nameTime.format(Date(start))}-part${part}-of-$totalParts-${System.currentTimeMillis()}.pdf"
        val document = PdfDocument()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 10f }
        try {
            for ((pageIndex, group) in images.chunked(2).withIndex()) {
                if (cancelled()) throw IOException("PDF export stopped")
                val page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, pageIndex + 1).create())
                val canvas = page.canvas
                paint.textSize = 17f
                canvas.drawText("Zvektra — Snapshot report${if (partial) " (partial)" else ""}", 30f, 32f, paint)
                paint.textSize = 10f
                canvas.drawText("${deviceName.take(30)} | Cam $camera | $timezone | Part $part/$totalParts | Page ${pageIndex + 1}", 30f, 51f, paint)
                canvas.drawText("${time.format(Date(start))} to ${time.format(Date(end))}", 30f, 67f, paint)
                canvas.drawText("People/vehicles; similar images grouped. Automated detections may miss objects.", 30f, 82f, paint)
                for ((index, image) in group.withIndex()) {
                    val options = BitmapFactory.Options().apply { inSampleSize = 2 }
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(image.second.absolutePath, bounds)
                    while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > 1600) options.inSampleSize *= 2
                    val bitmap = BitmapFactory.decodeFile(image.second.absolutePath, options)
                        ?: throw IOException("Report image could not be decoded")
                    try {
                        val top = 100f + index * 355f
                        canvas.drawText(time.format(Date(image.first)), 30f, top + 13f, paint)
                        val scale = minOf(535f / bitmap.width, 305f / bitmap.height)
                        val width = bitmap.width * scale
                        val height = bitmap.height * scale
                        val left = 30f + (535f - width) / 2
                        canvas.drawBitmap(bitmap, null, RectF(left, top + 24f, left + width, top + 24f + height), null)
                    } finally { bitmap.recycle() }
                }
                document.finishPage(page)
            }
            if (Build.VERSION.SDK_INT >= 29) {
                val resolver = context.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Zvektra")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IOException("Could not create PDF")
                try {
                    resolver.openOutputStream(uri)?.use { document.writeTo(it) } ?: throw IOException("Could not write PDF")
                    values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0)
                    if (resolver.update(uri, values, null, null) != 1) throw IOException("Could not publish PDF")
                } catch (error: Exception) { runCatching { resolver.delete(uri, null, null) }; throw error }
            } else {
                @Suppress("DEPRECATION")
                val folder = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Zvektra")
                if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Could not create report folder")
                val file = File(folder, name)
                try { file.outputStream().use { document.writeTo(it) } }
                catch (error: Exception) { file.delete(); throw error }
            }
        } finally { document.close() }
    }
}
