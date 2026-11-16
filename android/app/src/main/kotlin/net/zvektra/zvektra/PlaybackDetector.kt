package net.zvektra.zvektra

import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.FloatBuffer
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

/** Owned by the detection worker. Each model runs on the same decoded VLC frame. */
internal class PlaybackDetector(private val context: Context) : AutoCloseable {
    private val environment = OrtEnvironment.getEnvironment()
    private var people: OrtSession? = null
    private var plates: OrtSession? = null

    private fun load(name: String): OrtSession {
        val model = context.assets.open("detection/$name.onnx").use { it.readBytes() }
        return OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            environment.createSession(model, options)
        }
    }

    fun analyze(jpeg: ByteArray): List<Map<String, Any>> {
        val frame = requireNotNull(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)) {
            "Invalid VLC snapshot"
        }
        try {
            val personModel = people ?: load("people").also { people = it }
            val plateModel = plates ?: load("plates").also { plates = it }
            return buildList {
                for (box in peopleIn(frame, personModel)) {
                    snapshot(frame, box, "person")?.let { add(it) }
                }
                for (box in platesIn(frame, plateModel)) {
                    snapshot(frame, box, "licensePlate")?.let { add(it) }
                }
            }
        } finally {
            frame.recycle()
        }
    }

    private fun peopleIn(frame: Bitmap, model: OrtSession): List<RectF> {
        // SSD MobileNet consumes NHWC RGB bytes and returns normalized YXYX boxes.
        val size = 300
        val pixels = pixelsFor(frame, size, Rect(0, 0, size, size))
        val rgb = ByteArray(pixels.size * 3)
        pixels.forEachIndexed { i, pixel ->
            rgb[3 * i] = (pixel shr 16).toByte()
            rgb[3 * i + 1] = (pixel shr 8).toByte()
            rgb[3 * i + 2] = pixel.toByte()
        }
        return OnnxTensor.createTensor(
            environment, ByteBuffer.wrap(rgb), longArrayOf(1, 300, 300, 3), OnnxJavaType.UINT8,
        ).use { input ->
            model.run(mapOf("inputs" to input)).use { result ->
                @Suppress("UNCHECKED_CAST")
                val boxes = (result[0].value as Array<Array<FloatArray>>)[0]
                @Suppress("UNCHECKED_CAST")
                val classes = (result[1].value as Array<FloatArray>)[0]
                @Suppress("UNCHECKED_CAST")
                val scores = (result[2].value as Array<FloatArray>)[0]
                boxes.indices.filter { classes[it] == 1f && scores[it] >= 0.5f }.map { i ->
                    val (top, left, bottom, right) = boxes[i]
                    RectF(left * frame.width, top * frame.height,
                        right * frame.width, bottom * frame.height)
                }
            }
        }
    }

    private fun platesIn(frame: Bitmap, model: OrtSession): List<RectF> {
        // YOLOv9 consumes letterboxed NCHW RGB floats. NMS is part of the model.
        val size = 384
        val scale = size.toFloat() / maxOf(frame.width, frame.height)
        val width = (scale * frame.width).roundToInt().coerceIn(1, size)
        val height = (scale * frame.height).roundToInt().coerceIn(1, size)
        val left = (size - width) / 2
        val top = (size - height) / 2
        val pixels = pixelsFor(frame, size, Rect(left, top, left + width, top + height))
        val rgb = FloatArray(pixels.size * 3)
        pixels.forEachIndexed { i, pixel ->
            rgb[i] = Color.red(pixel) / 255f
            rgb[pixels.size + i] = Color.green(pixel) / 255f
            rgb[2 * pixels.size + i] = Color.blue(pixel) / 255f
        }
        return OnnxTensor.createTensor(
            environment, FloatBuffer.wrap(rgb), longArrayOf(1, 3, 384, 384),
        ).use { input ->
            model.run(mapOf("images" to input)).use { result ->
                @Suppress("UNCHECKED_CAST")
                val rows = result[0].value as Array<FloatArray>
                rows.filter { it[5] == 0f && it[6] >= 0.35f }.map { row ->
                    RectF((row[1] - left) / scale, (row[2] - top) / scale,
                        (row[3] - left) / scale, (row[4] - top) / scale)
                }
            }
        }
    }

    private fun pixelsFor(frame: Bitmap, size: Int, destination: Rect): IntArray {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.rgb(114, 114, 114))
            canvas.drawBitmap(frame, null, destination, Paint(Paint.FILTER_BITMAP_FLAG))
            return IntArray(size * size).also {
                bitmap.getPixels(it, 0, size, 0, 0, size, size)
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun snapshot(frame: Bitmap, box: RectF, kind: String): Map<String, Any>? {
        if (!box.left.isFinite() || !box.right.isFinite() ||
            !box.top.isFinite() || !box.bottom.isFinite()) return null
        val left = floor(box.left).toInt().coerceIn(0, frame.width)
        val top = floor(box.top).toInt().coerceIn(0, frame.height)
        val right = ceil(box.right).toInt().coerceIn(0, frame.width)
        val bottom = ceil(box.bottom).toInt().coerceIn(0, frame.height)
        val width = right - left
        val height = bottom - top
        if (width < 2 || height < 2) return null
        val scale = minOf(1f, 320f / maxOf(width, height))
        val crop = Bitmap.createBitmap(
            (width * scale).roundToInt().coerceAtLeast(1),
            (height * scale).roundToInt().coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        try {
            Canvas(crop).drawBitmap(frame, Rect(left, top, right, bottom),
                Rect(0, 0, crop.width, crop.height), Paint(Paint.FILTER_BITMAP_FLAG))
            val bytes = ByteArrayOutputStream()
            if (!crop.compress(Bitmap.CompressFormat.JPEG, 85, bytes)) return null
            return mapOf("kind" to kind, "snapshot" to bytes.toByteArray())
        } finally {
            crop.recycle()
        }
    }

    override fun close() {
        people?.close()
        plates?.close()
    }
}
