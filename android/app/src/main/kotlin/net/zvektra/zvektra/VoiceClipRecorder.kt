package net.zvektra.zvektra

import android.media.MediaRecorder
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

internal class VoiceClipRecorder(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "net.zvektra/voice_clip")
    private var clip: File? = null
    private var recorder: MediaRecorder? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> { start(); result.success(null) }
                    "stop" -> {
                        val file = checkNotNull(clip)
                        checkNotNull(recorder).stop()
                        val bytes = file.readBytes()
                        cancel()
                        result.success(bytes)
                    }
                    "cancel" -> { cancel(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                cancel()
                result.error("VOICE_CLIP", "Could not record the command", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun start() {
        cancel()
        val file = File.createTempFile("voice-", ".m4a", activity.cacheDir)
        clip = file
        val next = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(activity) else MediaRecorder()
        recorder = next
        next.setAudioSource(MediaRecorder.AudioSource.MIC)
        next.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        next.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        next.setAudioChannels(1)
        next.setAudioSamplingRate(16000)
        next.setAudioEncodingBitRate(32000)
        next.setOutputFile(file.absolutePath)
        next.prepare()
        next.start()
    }

    fun cancel() {
        recorder?.release()
        recorder = null
        clip?.delete()
        clip = null
    }

    fun close() {
        cancel()
        channel.setMethodCallHandler(null)
    }
}
