package com.whispertranscriber.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.preference.PreferenceManager
import com.whispertranscriber.R
import com.whispertranscriber.network.WhisperApiClient
import com.whispertranscriber.ui.MainActivity
import com.whispertranscriber.util.AudioRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

class FloatingOverlayService : Service() {

    companion object {
        const val CHANNEL_ID = "whisper_transcriber_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.whispertranscriber.STOP_OVERLAY"
    }

    private lateinit var windowManager: WindowManager
    private lateinit var bubbleView: View
    private var expandedView: View? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val audioRecorder = AudioRecorder()
    private var recordingJob: Job? = null

    private enum class State { IDLE, RECORDING, TRANSCRIBING }
    private var currentState = State.IDLE

    // Bubble drag tracking
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var hasMoved = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Tap the floating bubble to record"))
        createBubble()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        audioRecorder.cancel()
        recordingJob?.cancel()
        scope.cancel()
        try { windowManager.removeView(bubbleView) } catch (_: Exception) {}
        try { expandedView?.let { windowManager.removeView(it) } } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun createBubble() {
        val inflater = LayoutInflater.from(this)
        bubbleView = inflater.inflate(R.layout.overlay_bubble, null)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 200
        }

        val bubbleIcon = bubbleView.findViewById<ImageView>(R.id.bubble_icon)

        bubbleView.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    hasMoved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (dx * dx + dy * dy > 25) { // 5px threshold
                        hasMoved = true
                    }
                    params.x = initialX + dx.toInt()
                    params.y = initialY + dy.toInt()
                    windowManager.updateViewLayout(bubbleView, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!hasMoved) {
                        onBubbleTap()
                    }
                    true
                }
                else -> false
            }
        }

        // Long-press to show expanded panel or close
        bubbleView.setOnLongClickListener {
            if (expandedView == null) {
                showExpandedPanel()
            } else {
                hideExpandedPanel()
            }
            true
        }

        windowManager.addView(bubbleView, params)
    }

    private fun onBubbleTap() {
        when (currentState) {
            State.IDLE -> startRecording()
            State.RECORDING -> stopRecording()
            State.TRANSCRIBING -> { /* ignore taps while transcribing */ }
        }
    }

    private fun startRecording() {
        currentState = State.RECORDING
        updateBubbleState()
        updateNotification("Recording audio...")

        audioRecorder.startRecording()
        recordingJob = scope.launch(Dispatchers.IO) {
            audioRecorder.readLoop()
        }
    }

    private fun stopRecording() {
        currentState = State.TRANSCRIBING
        updateBubbleState()
        updateNotification("Transcribing...")

        recordingJob?.cancel()
        recordingJob = null

        val audioFile = File(cacheDir, "recording_${System.currentTimeMillis()}.wav")
        audioRecorder.stopRecording(audioFile)

        scope.launch {
            transcribeAudio(audioFile)
        }
    }

    private suspend fun transcribeAudio(audioFile: File) {
        val prefs = PreferenceManager.getDefaultSharedPreferences(this)
        val serverUrl = prefs.getString("server_url", "http://192.168.1.100:9000") ?: ""
        val endpoint = prefs.getString("api_endpoint", "/asr") ?: "/asr"
        val apiKey = prefs.getString("api_key", "") ?: ""
        val language = prefs.getString("language", "en") ?: "en"
        val outputFormat = prefs.getString("output_format", "txt") ?: "txt"
        val timeout = (prefs.getString("connection_timeout", "30") ?: "30").toLongOrNull() ?: 30
        val autoCopy = prefs.getBoolean("auto_copy", true)

        val client = WhisperApiClient(
            serverUrl = serverUrl,
            endpoint = endpoint,
            apiKey = apiKey,
            language = language,
            outputFormat = outputFormat,
            timeoutSeconds = timeout
        )

        val result = client.transcribe(audioFile)

        // Clean up audio file
        audioFile.delete()

        result.fold(
            onSuccess = { text ->
                currentState = State.IDLE
                updateBubbleState()
                updateNotification("Tap the floating bubble to record")

                if (autoCopy && text.isNotBlank()) {
                    copyToClipboard(text)
                    showToast("Copied: ${text.take(50)}${if (text.length > 50) "..." else ""}")
                }

                // Update expanded panel if visible
                updateExpandedPanel(text)
            },
            onFailure = { error ->
                currentState = State.IDLE
                updateBubbleState()
                updateNotification("Tap the floating bubble to record")
                showToast("Error: ${error.message}")
                updateExpandedPanel("Error: ${error.message}")
            }
        )
    }

    private fun updateBubbleState() {
        val bubbleIcon = bubbleView.findViewById<ImageView>(R.id.bubble_icon)
        when (currentState) {
            State.IDLE -> {
                bubbleIcon.setBackgroundResource(R.drawable.bubble_background)
                bubbleIcon.setImageResource(R.drawable.ic_mic)
            }
            State.RECORDING -> {
                bubbleIcon.setBackgroundResource(R.drawable.bubble_recording)
                bubbleIcon.setImageResource(R.drawable.ic_stop)
            }
            State.TRANSCRIBING -> {
                bubbleIcon.setBackgroundResource(R.drawable.bubble_transcribing)
                bubbleIcon.setImageResource(R.drawable.ic_mic)
            }
        }
    }

    private fun showExpandedPanel() {
        if (expandedView != null) return

        val inflater = LayoutInflater.from(this)
        expandedView = inflater.inflate(R.layout.overlay_expanded, null)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        expandedView?.findViewById<ImageButton>(R.id.btn_close_panel)?.setOnClickListener {
            hideExpandedPanel()
        }

        expandedView?.findViewById<ImageButton>(R.id.btn_copy)?.setOnClickListener {
            val text = expandedView?.findViewById<TextView>(R.id.transcription_text)?.text?.toString() ?: ""
            if (text.isNotBlank() && text != "Tap the mic to start recording…") {
                copyToClipboard(text)
                showToast("Copied to clipboard")
            }
        }

        windowManager.addView(expandedView, params)
    }

    private fun hideExpandedPanel() {
        expandedView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
        }
        expandedView = null
    }

    private fun updateExpandedPanel(text: String) {
        expandedView?.let {
            it.findViewById<TextView>(R.id.transcription_text)?.text = text
            val status = when (currentState) {
                State.IDLE -> "Ready"
                State.RECORDING -> "Recording..."
                State.TRANSCRIBING -> "Transcribing..."
            }
            it.findViewById<TextView>(R.id.status_indicator)?.text = status
        }
    }

    private fun copyToClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("Whisper Transcription", text)
        clipboard.setPrimaryClip(clip)
    }

    private fun showToast(message: String) {
        scope.launch(Dispatchers.Main) {
            Toast.makeText(this@FloatingOverlayService, message, Toast.LENGTH_SHORT).show()
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Whisper Transcriber overlay service"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, FloatingOverlayService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(openIntent)
            .addAction(
                Notification.Action.Builder(
                    null, "Stop", stopIntent
                ).build()
            )
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }
}
