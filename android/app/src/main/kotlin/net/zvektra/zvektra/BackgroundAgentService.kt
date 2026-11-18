package net.zvektra.zvektra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.NotificationCompat
import java.util.Locale
import java.util.concurrent.Executors

class BackgroundAgentService : Service() {
    companion object {
        private const val CHANNEL = "background_agent"
        private const val WORK_NOTIFICATION = 74
        private const val DONE_NOTIFICATION = 75
        private const val STOP = "net.zvektra.BACKGROUND_STOP"
        private const val PREFS = "background_agent"
        private const val RUNNING = "running"
        private const val MESSAGE = "message"
        @Volatile private var running = false

        internal fun status(context: Context): Map<String, Any> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return mapOf(
                RUNNING to running,
                MESSAGE to if (!running && prefs.getBoolean(RUNNING, false))
                    "Background analysis was interrupted." else prefs.getString(MESSAGE, "").orEmpty(),
            )
        }

        internal fun start(context: Context, sources: ArrayList<String>, start: Long,
                           end: Long, camera: Int, timezone: String, downloadPort: Int?): Boolean {
            if (running) return false
            running = true
            try {
                val intent = Intent(context, BackgroundAgentService::class.java)
                    .putStringArrayListExtra("sources", sources)
                    .putExtra("start", start)
                    .putExtra("end", end)
                    .putExtra("camera", camera)
                    .putExtra("timezone", timezone)
                    .putExtra("downloadPort", downloadPort ?: 0)
                androidx.core.content.ContextCompat.startForegroundService(context, intent)
            } catch (error: RuntimeException) {
                running = false
                throw error
            }
            return true
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private var wakeLock: PowerManager.WakeLock? = null
    private var voice: TextToSpeech? = null
    @Volatile private var cancelled = false
    private var working = false
    private var expired = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "Background Agent", NotificationManager.IMPORTANCE_LOW),
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            cancelled = true
            if (!working) stopSelf()
            return START_NOT_STICKY
        }
        if (working) return START_NOT_STICKY
        val sources = intent?.getStringArrayListExtra("sources")
        val start = intent?.getLongExtra("start", 0) ?: 0
        val end = intent?.getLongExtra("end", 0) ?: 0
        val camera = intent?.getIntExtra("camera", 0) ?: 0
        val timezone = intent?.getStringExtra("timezone") ?: "UTC"
        val downloadPort = intent?.getIntExtra("downloadPort", 0)?.takeIf { it in 1..65535 }
        if (sources.isNullOrEmpty() || start <= 0 || end <= start || camera <= 0) {
            running = false
            stopSelf()
            return START_NOT_STICKY
        }
        working = true
        running = true
        startForeground(WORK_NOTIFICATION, notification("Opening recording", 0))
        notifications.cancel(DONE_NOTIFICATION)
        saveStatus(true, "Background analysis is running.")
        val power = getSystemService(PowerManager::class.java)
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Zvektra:BackgroundAgent").apply {
            acquire(6 * 60 * 60 * 1000L)
        }
        worker.execute {
            cacheDir.listFiles()?.filter {
                it.name.startsWith("background-recording-") || it.name.startsWith("background-clip-")
            }?.forEach { it.delete() }
            var lastUpdate = 0L
            val result = BackgroundRecording(applicationContext, { cancelled }) { message, percent ->
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - lastUpdate >= 1000) {
                    lastUpdate = now
                    main.post {
                        if (working && !cancelled) notifications.notify(WORK_NOTIFICATION, notification(message, percent))
                    }
                }
            }.run(sources, start, end - start, camera, timezone, downloadPort)
            main.post { if (working) finish(result) }
        }
        return START_NOT_STICKY
    }

    private fun notification(message: String, percent: Int? = null): Notification {
        val launch = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("Zvektra Background Agent")
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setContentIntent(launch)
            .setOnlyAlertOnce(true)
            .setAutoCancel(percent == null)
        if (percent != null) {
            val stop = PendingIntent.getService(this, 1,
                Intent(this, BackgroundAgentService::class.java).setAction(STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            builder.setProgress(100, percent, false)
                .setOngoing(true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stop)
        }
        return builder.build()
    }

    private fun saveStatus(active: Boolean, message: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(RUNNING, active).putString(MESSAGE, message).apply()
    }

    private fun finish(result: BackgroundRecording.Result) {
        val count = if (result.saved == 1) "1 clip saved." else result.saved.toString() + " clips saved."
        val outcome = when {
            cancelled -> "Background analysis stopped."
            result.partial -> "Background analysis incomplete."
            else -> "Background analysis finished."
        }
        val message = "$outcome $count"
        val summary = listOfNotNull(message, result.details).joinToString("\n")
        saveStatus(false, summary)
        notifications.notify(DONE_NOTIFICATION, notification(summary))
        if (cancelled) {
            stopSelf()
            return
        }

        voice = TextToSpeech(applicationContext) { initialized ->
            main.post {
                val tts = voice ?: return@post
                if (initialized != TextToSpeech.SUCCESS || tts.setLanguage(Locale.US) < 0) {
                    stopSelf()
                    return@post
                }
                tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(id: String?) = Unit
                    override fun onDone(id: String?) { main.post { stopSelf() } }
                    @Deprecated("Android also calls the overload with an error code")
                    override fun onError(id: String?) { main.post { stopSelf() } }
                })
                if (tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, "background-result") != TextToSpeech.SUCCESS) {
                    stopSelf()
                }
            }
        }
        main.postDelayed({ stopSelf() }, 12000)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        cancelled = true
        expired = true
        saveStatus(false, "Background analysis reached Android's time limit. Check your gallery for saved clips.")
        notifications.notify(DONE_NOTIFICATION,
            notification("Background analysis reached Android's time limit. Check your gallery for saved clips."))
        stopSelf()
    }

    override fun onDestroy() {
        if (!expired && voice == null && working && status(this)[MESSAGE] == "Background analysis is running.") {
            saveStatus(false, "Background analysis was interrupted.")
        }
        cancelled = true
        working = false
        running = false
        main.removeCallbacksAndMessages(null)
        voice?.stop()
        voice?.shutdown()
        wakeLock?.let { if (it.isHeld) it.release() }
        worker.shutdown()
        super.onDestroy()
    }
}
