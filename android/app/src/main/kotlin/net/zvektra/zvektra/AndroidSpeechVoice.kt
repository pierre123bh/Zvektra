package net.zvektra.zvektra

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Uses the phone's installed recognition provider. Language detection and switching
// require Android 14+ AND support from that provider; dialect quality is not guaranteed.
class AndroidSpeechVoice(
    private val activity: MainActivity,
    messenger: BinaryMessenger
) : RecognitionListener {
    private val channel = MethodChannel(messenger, "net.zvektra/speech")
    private var recognizer: SpeechRecognizer? = null
    private var listening = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
                        result.error("NO_ENGINE", "Install or enable an Android speech recognition service", null)
                    } else {
                        try {
                            cancel()
                            recognizer = SpeechRecognizer.createSpeechRecognizer(activity)
                            recognizer?.setRecognitionListener(this)
                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                                if (Build.VERSION.SDK_INT >= 34) {
                                    putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
                                    putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH, true)
                                    putStringArrayListExtra(
                                        RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,
                                        arrayListOf("en-US", "en-GB", "fr-FR", "ar-LB", "ar-SA")
                                    )
                                }
                            }
                            listening = true
                            recognizer?.startListening(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            cancel()
                            result.error("START_FAILED", e.message, null)
                        }
                    }
                }
                "stop" -> {
                    if (listening) recognizer?.stopListening()
                    listening = false
                    result.success(null)
                }
                "cancel" -> { cancel(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    fun cancel() {
        listening = false
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    fun close() {
        cancel()
        channel.setMethodCallHandler(null)
    }

    override fun onResults(results: Bundle?) {
        listening = false
        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull().orEmpty()
        if (text.isNotBlank()) channel.invokeMethod("recognized", text)
        else channel.invokeMethod("speechError", "No speech detected")
    }
    override fun onError(error: Int) {
        listening = false
        channel.invokeMethod("speechError", "Recognition error $error")
    }
    override fun onReadyForSpeech(params: Bundle?) {}
    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEndOfSpeech() {}
    override fun onPartialResults(partialResults: Bundle?) {}
    override fun onEvent(eventType: Int, params: Bundle?) {}
}
