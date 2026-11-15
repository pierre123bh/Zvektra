package net.zvektra.zvektra

import android.annotation.SuppressLint
import android.app.Activity
import android.content.res.AssetManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.annotation.Keep
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class WhisperVoice(private val activity: Activity, messenger: BinaryMessenger) {
    private class Capture(val recorder: AudioRecord) {
        val running = AtomicBoolean(true)
        val pcm = ShortArray(16000 * 12)
        var count = 0
        var failed = false
    }

    private val channel = MethodChannel(messenger, "net.zvektra/whisper")
    private val worker = Executors.newSingleThreadExecutor()
    private var capture: Capture? = null
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop" -> stop(result)
                "cancel" -> { cancel(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission") // Flutter requests runtime permission before start.
    private fun start(result: MethodChannel.Result) {
        if (capture != null || pending != null) {
            result.error("busy", "Wait for the previous recording.", null)
            return
        }
        val minimum = AudioRecord.getMinBufferSize(
            16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (minimum <= 0) {
            result.error("mic", "This device cannot record the required audio format.", null)
            return
        }

        var recorder: AudioRecord? = null
        try {
            val audio = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minimum, 4096)
            )
            recorder = audio
            check(audio.state == AudioRecord.STATE_INITIALIZED)
            audio.startRecording()
            check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            val recording = Capture(audio)
            capture = recording
            worker.execute { record(recording) }
            result.success(null)
        } catch (_: Exception) {
            recorder?.release()
            capture = null
            result.error("mic", "Could not start the microphone. Check its permission.", null)
        }
    }

    private fun record(recording: Capture) {
        try {
            while (recording.running.get() && recording.count < recording.pcm.size) {
                val count = recording.recorder.read(
                    recording.pcm, recording.count,
                    minOf(1024, recording.pcm.size - recording.count),
                    AudioRecord.READ_NON_BLOCKING
                )
                if (count < 0) {
                    recording.failed = true
                    break
                }
                recording.count += count
                if (count == 0) Thread.sleep(10)
            }
        } catch (_: Exception) {
            recording.failed = true
        } finally {
            try {
                recording.recorder.stop()
            } catch (_: IllegalStateException) {
                // The microphone may have stopped at the Android system level.
            }
            recording.recorder.release()
        }
    }

    private fun stop(result: MethodChannel.Result) {
        val recording = capture
        if (recording == null || pending != null) {
            result.error("inactive", "Start a recording first.", null)
            return
        }
        capture = null
        recording.running.set(false)
        pending = result
        worker.execute {
            val outcome = runCatching {
                check(!recording.failed) { "Microphone recording failed." }
                if (recording.count < 3200 ||
                    (0 until recording.count).none { kotlin.math.abs(recording.pcm[it].toInt()) > 100 }
                ) {
                    ""
                } else {
                    val text = WhisperNative.transcribe(activity.assets, recording.pcm, recording.count)
                    checkNotNull(text) { "Whisper could not read or transcribe the audio." }
                    text.toString(Charsets.UTF_8).trim()
                }
            }
            recording.pcm.fill(0)
            activity.runOnUiThread {
                if (pending === result) {
                    pending = null
                    outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = {
                            result.error("whisper", "Offline transcription failed. Try again.", null)
                        }
                    )
                }
            }
        }
    }

    fun cancel() {
        capture?.let { recording ->
            recording.running.set(false)
            worker.execute { recording.pcm.fill(0) }
        }
        capture = null
        pending?.error("cancelled", "Voice recording cancelled.", null)
        pending = null
    }

    fun close() {
        channel.setMethodCallHandler(null)
        cancel()
        worker.shutdown()
    }
}

@Keep
internal object WhisperNative {
    init { System.loadLibrary("zvektra_whisper") }

    external fun transcribe(assets: AssetManager, pcm: ShortArray, sampleCount: Int): ByteArray?
}
