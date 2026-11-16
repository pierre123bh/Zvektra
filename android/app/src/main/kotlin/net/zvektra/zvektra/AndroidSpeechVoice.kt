package net.zvektra.zvektra

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
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

    private val handler = Handler(Looper.getMainLooper())
    private data class Speech(val id: String, val text: String, val locale: String,
        val result: MethodChannel.Result)
    private var speechSequence = 0
    private var pendingSpeech: Speech? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val speechTimeout = Runnable { stopSpeaking() }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text")
                    val locale = call.argument<String>("locale")
                    if (text == null || locale == null) result.success(false)
                    else speak(text, locale, result)
                }
                "start" -> {
                    if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
                        result.error("NO_ENGINE", "Install or enable an Android speech recognition service", null)
                    } else {
                        try {
                            cancel()
                            val session = SpeechRecognizer.createSpeechRecognizer(activity)
                            recognizer = session
                            session.setRecognitionListener(object : RecognitionListener by this@AndroidSpeechVoice {
                                override fun onResults(results: Bundle?) {
                                    if (recognizer === session) this@AndroidSpeechVoice.onResults(results)
                                }

                                override fun onError(error: Int) {
                                    if (recognizer === session) this@AndroidSpeechVoice.onError(error)
                                }
                            })
                            val locale = call.argument<String>("locale") ?: "en-US"
                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                                if (Build.VERSION.SDK_INT >= 34) {
                                    putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
                                    putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH, true)
                                    putStringArrayListExtra(
                                        RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,
                                        arrayListOf(locale, if (locale == "ar-LB") "en-US" else "ar-LB", "ar-SA")
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
                    try {
                        if (listening) recognizer?.stopListening()
                        listening = false
                        result.success(null)
                    } catch (_: Exception) {
                        cancel()
                        result.error("STOP_FAILED", "Could not finish speech recognition", null)
                    }
                }
                "cancel" -> { cancel(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun speak(text: String, locale: String, result: MethodChannel.Result) {
        stopSpeaking()
        pendingSpeech = Speech("zvektra-${++speechSequence}", text, locale, result)
        handler.postDelayed(speechTimeout, 6000)
        if (tts == null) {
            tts = TextToSpeech(activity.applicationContext) { status ->
                handler.post {
                    val engine = tts ?: return@post
                    if (status != TextToSpeech.SUCCESS) {
                        engine.shutdown()
                        tts = null
                        stopSpeaking()
                        return@post
                    }
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String) {}
                        override fun onDone(utteranceId: String) {
                            handler.post { finishSpeaking(utteranceId, true) }
                        }
                        @Deprecated("Legacy TextToSpeech callback")
                        override fun onError(utteranceId: String) {
                            handler.post { finishSpeaking(utteranceId, false) }
                        }
                    })
                    ttsReady = true
                    speakPending(engine)
                }
            }
        } else if (ttsReady) {
            tts?.let { speakPending(it) }
        }
    }

    private fun speakPending(engine: TextToSpeech) {
        val speech = pendingSpeech ?: return
        try {
            val locale = Locale.forLanguageTag(speech.locale)
            val available = engine.setLanguage(locale) >= TextToSpeech.LANG_AVAILABLE ||
                (locale.language == "ar" && engine.setLanguage(Locale("ar")) >= TextToSpeech.LANG_AVAILABLE)
            if (!available || engine.speak(speech.text, TextToSpeech.QUEUE_FLUSH, null, speech.id)
                != TextToSpeech.SUCCESS) finishSpeaking(speech.id, false)
        } catch (_: Exception) {
            finishSpeaking(speech.id, false)
        }
    }

    private fun finishSpeaking(id: String, success: Boolean) {
        val speech = pendingSpeech ?: return
        if (speech.id != id) return
        pendingSpeech = null
        handler.removeCallbacks(speechTimeout)
        speech.result.success(success)
    }

    private fun stopSpeaking() {
        pendingSpeech?.let {
            runCatching { tts?.stop() }
            finishSpeaking(it.id, false)
        }
    }

    fun cancel() {
        stopSpeaking()
        listening = false
        val session = recognizer
        recognizer = null
        if (session != null) {
            runCatching { session.cancel() }
            runCatching { session.destroy() }
        }
    }

    fun close() {
        cancel()
        channel.setMethodCallHandler(null)
        tts?.shutdown()
        tts = null
        ttsReady = false
    }

    override fun onResults(results: Bundle?) {
        listening = false
        val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull().orEmpty()
        if (text.isNotBlank()) {
            val confidence = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                ?.firstOrNull()?.toDouble()
            channel.invokeMethod("recognized", mapOf("text" to text, "confidence" to confidence))
        } else {
            channel.invokeMethod("speechError", "No speech detected")
        }
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
