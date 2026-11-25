package com.kee.app

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener as VoskRecognitionListener
import org.vosk.android.SpeechService as VoskSpeechService
import java.util.*

class KeeBackgroundVoiceService : Service(), TextToSpeech.OnInitListener {

    companion object {
        const val CHANNEL_ID = "kee_voice_channel"
        const val NOTIFICATION_ID = 9001
        const val ACTION_START_LISTENING = "com.kee.app.START_LISTENING"
        const val ACTION_STOP_LISTENING = "com.kee.app.STOP_LISTENING"
        const val ACTION_PAUSE_LISTENING = "com.kee.app.PAUSE_LISTENING"
        const val ACTION_RESUME_LISTENING = "com.kee.app.RESUME_LISTENING"

        var isRunning = false
        var isOverlayShowing = false

        // Callback to communicate with Flutter engine if active
        var queryHandler: ((String, (String) -> Unit) -> Unit)? = null
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    // Offline single-mic Vosk wake-word engine (zero system chimes)
    private var voskModel: Model? = null
    private var voskSpeechService: VoskSpeechService? = null
    @Volatile
    private var isVoskLoading = false
    @Volatile
    private var isVoskListening = false

    private var isListeningForWakeWord = true
    private var isPaused = false
    private var isProcessingRequest = false
    private var isSpeaking = false
    private var consecutiveErrors = 0

    private val mainHandler = Handler(Looper.getMainLooper())
    private val restartRunnable = Runnable {
        if (isRunning && !isPaused && !isProcessingRequest && !isSpeaking && !isOverlayShowing) {
            startWakeWordListening()
        }
    }
    private val wakeWords = listOf(
        "what's up key",
        "what's up kee",
        "what's up kay",
        "what's up k",
        "whats up key",
        "whats up kee",
        "whats up kay",
        "whats up k",
        "what up key",
        "what up kee",
        "what up kay",
        "what up k",
        "hi key",
        "hi kee",
        "hey key",
        "hey kee",
        "hello key",
        "hello kee",
        "ok key",
        "ok kee",
        "hi kay",
        "hi k",
        "hey kay",
        "hey k",
        "ok kay",
        "ok k",
        "key",
        "kee"
    )

    // UI elements in floating overlay
    private var tvStatus: TextView? = null
    private var tvTranscript: TextView? = null
    private var orbView: View? = null
    private var orbRingView: View? = null
    private var btnActionMic: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        tts = TextToSpeech(this, this)
        initSpeechRecognizer()
        initVoskWakeWord()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildForegroundNotification()
        startForeground(NOTIFICATION_ID, notification)

        when (intent?.action) {
            ACTION_STOP_LISTENING -> {
                mainHandler.removeCallbacks(restartRunnable)
                stopVoskListening()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE_LISTENING -> {
                isPaused = true
                mainHandler.removeCallbacks(restartRunnable)
                stopVoskListening()
                mainHandler.post { speechRecognizer?.cancel() }
                return START_STICKY
            }
            ACTION_RESUME_LISTENING, ACTION_START_LISTENING, null -> {
                isPaused = false
                consecutiveErrors = 0
                startWakeWordListening()
                return START_STICKY
            }
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Kee Background Assistant",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Kee voice detection active in the background"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Kee is running in background")
            .setContentText("Say \"Hi Kee\" or \"What's up K\" anytime")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun initSpeechRecognizer() {
        mainHandler.post {
            try {
                if (SpeechRecognizer.isRecognitionAvailable(this)) {
                    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                    speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                        override fun onReadyForSpeech(params: Bundle?) {
                            consecutiveErrors = 0
                        }
                        override fun onBeginningOfSpeech() {}
                        override fun onRmsChanged(rmsdB: Float) {
                            if (isOverlayShowing) {
                                animateOrb(rmsdB)
                            }
                        }
                        override fun onBufferReceived(buffer: ByteArray?) {}
                        override fun onEndOfSpeech() {}
                        override fun onError(error: Int) {
                            handleSpeechError(error)
                        }
                        override fun onResults(results: Bundle?) {
                            consecutiveErrors = 0
                            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                handleSpeechText(matches[0], true)
                            } else {
                                restartListeningAfterDelay(1000)
                            }
                        }
                        override fun onPartialResults(partialResults: Bundle?) {
                            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                handleSpeechText(matches[0], false)
                            }
                        }
                        override fun onEvent(eventType: Int, params: Bundle?) {}
                    })
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun initVoskWakeWord() {
        if (voskModel != null || isVoskLoading) return
        if (!KeeWakeWordModelManager.isModelReady(this)) return

        isVoskLoading = true
        Thread {
            try {
                val modelDir = KeeWakeWordModelManager.getModelDir(this)
                val model = Model(modelDir.absolutePath)
                voskModel = model
                // Grammar-constrained recognizer using standard English lexicon words ("key"/"kay" + "kee"/"k")
                val grammar = """["what's up key", "what's up kee", "what's up kay", "what's up k", "what up key", "what up kay", "hi key", "hi kee", "hey key", "hey kee", "hello key", "hello kee", "ok key", "ok kee", "hi kay", "hey kay", "ok kay", "key", "[unk]"]"""
                val recognizer = Recognizer(model, 16000.0f, grammar)
                voskSpeechService = VoskSpeechService(recognizer, 16000.0f)
                isVoskLoading = false

                if (isRunning && !isPaused && !isOverlayShowing && isListeningForWakeWord) {
                    mainHandler.post { startWakeWordListening() }
                }
            } catch (e: Exception) {
                isVoskLoading = false
                e.printStackTrace()
            }
        }.start()
    }

    private val voskListener = object : VoskRecognitionListener {
        override fun onPartialResult(hypothesis: String?) {
            handleVoskHypothesis(hypothesis, false)
        }

        override fun onResult(hypothesis: String?) {
            handleVoskHypothesis(hypothesis, true)
        }

        override fun onFinalResult(hypothesis: String?) {
            handleVoskHypothesis(hypothesis, true)
        }

        override fun onError(exception: Exception?) {
            isVoskListening = false
        }

        override fun onTimeout() {
            isVoskListening = false
        }
    }

    private fun handleVoskHypothesis(hypothesis: String?, isFinal: Boolean) {
        if (!isListeningForWakeWord || isPaused || isOverlayShowing || hypothesis.isNullOrBlank()) return
        try {
            val json = JSONObject(hypothesis)
            val raw = json.optString("partial", "").ifEmpty { json.optString("text", "") }
            val cleaned = raw.replace("[unk]", "").trim().lowercase(Locale.ROOT)
            if (cleaned.isEmpty()) return

            for (wakeWord in wakeWords) {
                val pattern = Regex("\\b${Regex.escape(wakeWord)}\\b")
                if (pattern.containsMatchIn(cleaned)) {
                    stopVoskListening()
                    triggerWakeWordDetected(cleaned, wakeWord)
                    return
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun stopVoskListening() {
        try {
            if (isVoskListening) {
                voskSpeechService?.stop()
                isVoskListening = false
            }
        } catch (_: Exception) {
            isVoskListening = false
        }
    }

    private fun startWakeWordListening() {
        if (isPaused || !isRunning || isOverlayShowing) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return
        }

        isListeningForWakeWord = true
        isProcessingRequest = false

        val service = voskSpeechService
        if (service == null) {
            if (!isVoskLoading && KeeWakeWordModelManager.isModelReady(this)) {
                initVoskWakeWord()
            }
            return
        }

        if (!isVoskListening) {
            try {
                isVoskListening = service.startListening(voskListener)
            } catch (e: Exception) {
                isVoskListening = false
                e.printStackTrace()
            }
        }
    }

    private fun handleSpeechText(text: String, isFinal: Boolean) {
        val lower = text.trim().lowercase(Locale.ROOT)

        if (isListeningForWakeWord) {
            // Check for wake words: "Hi Kee", "What's up K", etc. using word boundaries
            for (wakeWord in wakeWords) {
                val pattern = Regex("\\b${Regex.escape(wakeWord)}\\b")
                if (pattern.containsMatchIn(lower)) {
                    triggerWakeWordDetected(text, wakeWord)
                    return
                }
            }
            if (isFinal) {
                restartListeningAfterDelay(200)
            }
        } else {
            // User is speaking to the assistant in the overlay
            if (tvTranscript != null) {
                mainHandler.post {
                    tvTranscript?.text = "\"$text\""
                }
            }

            if (isFinal && text.trim().isNotEmpty()) {
                processSpokenQuery(text)
            }
        }
    }

    private fun triggerWakeWordDetected(fullText: String, matchedWakeWord: String) {
        vibratePhone()

        isListeningForWakeWord = false
        mainHandler.post {
            speechRecognizer?.stopListening()
            showFloatingOverlay()
        }

        // Check if user spoke query in the same breath (e.g. "Hi Kee remind me to call David")
        val lower = fullText.lowercase(Locale.ROOT)
        val idx = lower.indexOf(matchedWakeWord)
        val trailing = fullText.substring(idx + matchedWakeWord.length).trim()

        if (trailing.isNotEmpty()) {
            processSpokenQuery(trailing)
        } else {
            startListeningForUserQuery()
        }
    }

    private fun startListeningForUserQuery() {
        mainHandler.post {
            updateOverlayState("Listening...", "#E8D0B2", "Speak")
            tvTranscript?.text = "Speak naturally..."
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }

        mainHandler.postDelayed({
            try {
                speechRecognizer?.startListening(intent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, 300)
    }

    private fun processSpokenQuery(query: String) {
        if (isProcessingRequest) return
        isProcessingRequest = true

        mainHandler.post {
            updateOverlayState("Understanding...", "#F59E0B", "Wait")
            speechRecognizer?.stopListening()
        }

        // Delegate query to Flutter's KeeConversationEngine if alive
        val handler = queryHandler
        if (handler != null) {
            handler(query) { response ->
                mainHandler.post {
                    displayAndSpeakResponse(response)
                }
            }
        } else {
            // Fallback response if Flutter engine is unattached
            val fallback = "I've noted: $query. You can review it inside Kee."
            mainHandler.post {
                displayAndSpeakResponse(fallback)
            }
        }
    }

    private fun displayAndSpeakResponse(reply: String) {
        isProcessingRequest = false
        isSpeaking = true

        updateOverlayState("Kee Speaking", "#34D399", "Interrupt")
        tvTranscript?.text = reply

        // Speak reply using native Android TTS
        if (isTtsReady && tts != null) {
            tts?.speak(reply, TextToSpeech.QUEUE_FLUSH, null, "KEE_REPLY")
        }
    }

    private fun updateOverlayState(statusText: String, accentHex: String, micLabel: String) {
        tvStatus?.text = statusText
        btnActionMic?.text = micLabel
        val color = Color.parseColor(accentHex)
        (orbView?.background as? GradientDrawable)?.setColor(color)
        (orbRingView?.background as? GradientDrawable)?.setStroke(3, Color.argb(110, Color.red(color), Color.green(color), Color.blue(color)))
    }

    private fun handleSpeechError(error: Int) {
        if (isPaused || !isRunning) return

        if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            stopSelf()
            return
        }

        if (isListeningForWakeWord) {
            if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                // Normal silence timeout — wait 1.5s before next window instead of hammering mic every 500ms
                consecutiveErrors = 0
                restartListeningAfterDelay(1500)
            } else {
                // Busy / audio / network error — exponential backoff (2s, 4s, 8s, max 15s)
                consecutiveErrors++
                val backoffMs = (2000L * (1 shl consecutiveErrors.coerceAtMost(3))).coerceAtMost(15000L)
                restartListeningAfterDelay(backoffMs)
            }
        } else {
            if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                mainHandler.post {
                    updateOverlayState("Tap Speak to ask", "#E8D0B2", "Speak")
                }
            } else {
                mainHandler.post {
                    updateOverlayState("Tap Speak to retry", "#EF4444", "Retry")
                }
            }
        }
    }

    private fun restartListeningAfterDelay(delayMs: Long) {
        mainHandler.removeCallbacks(restartRunnable)
        if (!isPaused && isRunning) {
            mainHandler.postDelayed(restartRunnable, delayMs)
        }
    }

    private fun vibratePhone() {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(80)
            }
        } catch (_: Exception) {}
    }

    // ─────────────────────────────────────────────────────────────
    // FLOATING SYSTEM OVERLAY (outside the Kee app)
    // ─────────────────────────────────────────────────────────────

    private fun showFloatingOverlay() {
        if (!Settings.canDrawOverlays(this)) return
        if (overlayView != null) return

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val layoutParamsType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val cardWidth = (resources.displayMetrics.widthPixels * 0.92f).toInt()
        val params = WindowManager.LayoutParams(
            cardWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutParamsType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = 72
        }

        overlayParams = params
        overlayView = createOverlayView()
        windowManager?.addView(overlayView, params)
        isOverlayShowing = true
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun createOverlayView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(16))
            val bg = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#1B1714"), Color.parseColor("#110E0C"))
            ).apply {
                cornerRadius = dp(26).toFloat()
                setStroke(dp(1), Color.parseColor("#473B2D"))
            }
            background = bg
            elevation = dp(16).toFloat()
        }

        // Top drag handle bar
        val dragPill = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(36), dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(10)
            }
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#4A3F32"))
                cornerRadius = dp(2).toFloat()
            }
        }
        root.addView(dragPill)

        // Header: Glowing Orb + Status + Open Kee + Close
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val orbContainer = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(34), dp(34)).apply {
                marginEnd = dp(10)
            }
        }

        orbRingView = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(34), dp(34), Gravity.CENTER)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke(3, Color.argb(110, 232, 208, 178))
            }
        }
        orbContainer.addView(orbRingView)

        orbView = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E8D0B2"))
            }
        }
        orbContainer.addView(orbView)
        header.addView(orbContainer)

        val titleCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        val tvBrand = TextView(this).apply {
            text = "Kee"
            setTextColor(Color.parseColor("#F5EFE6"))
            textSize = 13f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        titleCol.addView(tvBrand)

        tvStatus = TextView(this).apply {
            text = "Listening..."
            setTextColor(Color.parseColor("#CBB89D"))
            textSize = 11f
        }
        titleCol.addView(tvStatus)
        header.addView(titleCol)

        // Speak / Interrupt pill
        btnActionMic = TextView(this).apply {
            text = "Speak"
            textSize = 11f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setTextColor(Color.parseColor("#12100E"))
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(6), dp(12), dp(6))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E8D0B2"))
                cornerRadius = dp(16).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(8)
            }
            setOnClickListener {
                tts?.stop()
                isSpeaking = false
                isProcessingRequest = false
                startListeningForUserQuery()
            }
        }
        header.addView(btnActionMic)

        // Open App pill
        val btnOpenApp = TextView(this).apply {
            text = "Open"
            textSize = 11f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setTextColor(Color.parseColor("#E8D0B2"))
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(6), dp(12), dp(6))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#282119"))
                cornerRadius = dp(16).toFloat()
                setStroke(1, Color.parseColor("#544636"))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                marginEnd = dp(8)
            }
            setOnClickListener {
                launchFullApp()
            }
        }
        header.addView(btnOpenApp)

        // Circular Close Button
        val btnClose = TextView(this).apply {
            text = "✕"
            textSize = 13f
            setTextColor(Color.parseColor("#C2B5A3"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dp(28), dp(28))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#241E18"))
            }
            setOnClickListener {
                dismissOverlay()
            }
        }
        header.addView(btnClose)

        root.addView(header)

        // Transcript / Answer display
        tvTranscript = TextView(this).apply {
            text = "Speak naturally..."
            setTextColor(Color.parseColor("#F5EFE6"))
            textSize = 14.5f
            setLineSpacing(dp(2).toFloat(), 1.15f)
            setPadding(dp(4), dp(12), dp(4), dp(4))
            maxLines = 5
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        root.addView(tvTranscript)

        // Allow dragging the floating bubble vertically/horizontally
        var initialY = 0
        var initialTouchY = 0f
        root.setOnTouchListener { _, event ->
            val p = overlayParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = p.y
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = (initialTouchY - event.rawY).toInt()
                    p.y = (initialY + dy).coerceIn(dp(24), resources.displayMetrics.heightPixels - dp(180))
                    windowManager?.updateViewLayout(root, p)
                    true
                }
                else -> false
            }
        }

        return root
    }

    private fun animateOrb(rmsdB: Float) {
        val scale = (1.0f + (rmsdB / 15.0f).coerceIn(0f, 0.5f))
        orbView?.animate()?.scaleX(scale)?.scaleY(scale)?.setDuration(80)?.start()
        orbRingView?.animate()?.scaleX(scale * 1.15f)?.scaleY(scale * 1.15f)?.setDuration(80)?.start()
    }

    private fun launchFullApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("route", "/ask-kee")
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
        }
        dismissOverlay()
    }

    fun dismissOverlay() {
        if (overlayView != null && windowManager != null) {
            try {
                windowManager?.removeView(overlayView)
            } catch (_: Exception) {}
            overlayView = null
            isOverlayShowing = false
        }

        // Interrupt TTS if active
        tts?.stop()
        isSpeaking = false

        // Resume background wake word listening
        startWakeWordListening()
    }

    // ─────────────────────────────────────────────────────────────
    // TTS LISTENER
    // ─────────────────────────────────────────────────────────────

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.US
            tts?.setSpeechRate(1.0f)
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    isSpeaking = true
                }
                override fun onDone(utteranceId: String?) {
                    isSpeaking = false
                    mainHandler.postDelayed({
                        if (isOverlayShowing && !isProcessingRequest) {
                            startListeningForUserQuery()
                        }
                    }, 400)
                }
                override fun onError(utteranceId: String?) {
                    isSpeaking = false
                }
            })
            isTtsReady = true
        }
    }

    override fun onDestroy() {
        isRunning = false
        isPaused = true
        mainHandler.removeCallbacksAndMessages(null)
        stopVoskListening()
        try {
            voskSpeechService?.shutdown()
            voskModel?.close()
        } catch (_: Exception) {}
        dismissOverlay()
        speechRecognizer?.destroy()
        tts?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
