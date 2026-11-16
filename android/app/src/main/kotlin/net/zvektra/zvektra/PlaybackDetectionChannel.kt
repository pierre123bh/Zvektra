package net.zvektra.zvektra

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal class PlaybackDetectionChannel(context: Context, messenger: BinaryMessenger) {
    private val application = context.applicationContext
    private val channel = MethodChannel(messenger, "net.zvektra/playback_detection")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var detector: PlaybackDetector? = null
    private var busy = false
    private var closed = false

    init {
        channel.setMethodCallHandler { call, reply ->
            val frame = call.arguments as? ByteArray
            when {
                call.method != "analyze" -> reply.notImplemented()
                frame == null || frame.isEmpty() -> reply.error("frame", "Missing playback frame", null)
                busy -> reply.error("busy", "Previous frame still processing", null)
                else -> {
                    busy = true
                    worker.execute {
                        val outcome = try {
                            val active = detector ?: PlaybackDetector(application).also { detector = it }
                            Result.success(active.analyze(frame))
                        } catch (error: Exception) {
                            Result.failure(error)
                        } catch (error: LinkageError) {
                            Result.failure(error)
                        }
                        main.post {
                            busy = false
                            if (!closed) outcome.fold(
                                onSuccess = { reply.success(it) },
                                onFailure = {
                                    Log.e("PlaybackDetection", "Frame inference failed", it)
                                    reply.error("inference", "Playback detection failed", null)
                                },
                            )
                        }
                    }
                }
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        worker.execute { detector?.close() }
        worker.shutdown()
    }
}
