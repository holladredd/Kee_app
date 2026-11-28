package com.kee.app

import android.Manifest
import android.animation.ValueAnimator
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import android.view.*
import android.view.animation.LinearInterpolator
import android.widget.*
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener as VoskRecognitionListener
import org.vosk.android.SpeechService as VoskSpeechService
import java.util.*
import kotlin.math.*

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

        @Volatile
        var instance: KeeBackgroundVoiceService? = null

        @Volatile
        var isFlutterSessionActive = false

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
    private var isOverlayCapturingSpeech = false
    private var isSpeechRecognizerActive = false
    private var consecutiveErrors = 0
    private var lastWakeActivationMs = 0L
    private val wakeCooldownMs = 2500L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var voskConsecutiveErrors = 0
    private val restartRunnable = Runnable {
        if (isRunning && !isPaused && !isFlutterSessionActive && !isProcessingRequest && !isSpeaking && !isOverlayShowing) {
            startWakeWordListening()
        }
    }
    private val autoDismissOverlayRunnable = Runnable {
        if (isRunning && isOverlayShowing && !isProcessingRequest && !isSpeaking && !isOverlayCapturingSpeech) {
            dismissOverlay(resumeWakeWord = true)
        }
    }

    private fun scheduleAutoDismissOverlay(delayMs: Long = 2000L) {
        mainHandler.removeCallbacks(autoDismissOverlayRunnable)
        if (isRunning && isOverlayShowing) {
            mainHandler.postDelayed(autoDismissOverlayRunnable, delayMs)
        }
    }

    private fun cancelAutoDismissOverlay() {
        mainHandler.removeCallbacks(autoDismissOverlayRunnable)
    }
    // Primary wake phrase only ("Hi Kee"; "hi key" included solely as phonetic
    // equivalent for Vosk's standard English dictionary). No short matches.
    private val wakeWords = listOf(
        "hi kee",
        "hi key"
    )

    // ── Overlay UI references ─────────────────────────────────────────────────
    private var orbAnimView: KeeHolographicOrbView? = null
    private var userRow: View? = null
    private var tvUserTranscript: TextView? = null
    private var keeRow: View? = null
    private var tvKeeResponse: TextView? = null
    private var tvStatus: TextView? = null
    private var btnActionMic: TextView? = null
    private var btnRetry: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null
    // Preserved query state for safe Retry without duplicating successful actions
    private var lastUserQuery: String? = null
    private var lastQuerySucceeded: Boolean = false
    private var lastFailureWasSpeech: Boolean = false

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        instance = this
        createNotificationChannel()
        tts = TextToSpeech(this, this)
        initSpeechRecognizer()
        initVoskWakeWord()
    }

    /**
     * Synchronously pauses Vosk wake-word listening and invokes [onReleased] only
     * after [voskSpeechService] has stopped and released the microphone.
     */
    fun pauseAndReleaseMic(onReleased: () -> Unit) {
        mainHandler.post {
            isPaused = true
            isFlutterSessionActive = true
            mainHandler.removeCallbacks(restartRunnable)
            stopVoskListening()
            speechRecognizer?.cancel()
            onReleased()
        }
    }

    /**
     * Resumes Vosk wake-word listening when the Flutter voice session finishes.
     */
    fun resumeAfterFlutterSession() {
        mainHandler.post {
            isFlutterSessionActive = false
            isPaused = false
            voskConsecutiveErrors = 0
            startWakeWordListening()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildForegroundNotification()
        startForeground(NOTIFICATION_ID, notification)

        when (intent?.action) {
            ACTION_STOP_LISTENING -> {
                mainHandler.removeCallbacksAndMessages(null)
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
                if (isFlutterSessionActive) {
                    Log.d("KeeVoiceService", "Ignoring wake-word resume while Flutter voice session is active")
                    return START_STICKY
                }
                isPaused = false
                consecutiveErrors = 0
                voskConsecutiveErrors = 0
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
            .setContentText("Say \"Hi Kee\" anytime")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun initSpeechRecognizer() {
        mainHandler.post {
            try {
                speechRecognizer?.destroy()
                speechRecognizer = null
                isSpeechRecognizerActive = false
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
                            isSpeechRecognizerActive = false
                            handleSpeechError(error)
                        }
                        override fun onResults(results: Bundle?) {
                            consecutiveErrors = 0
                            isSpeechRecognizerActive = false
                            isOverlayCapturingSpeech = false
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
                } else {
                    Log.e("KeeVoiceService", "SpeechRecognizer.isRecognitionAvailable returned false")
                }
            } catch (e: Exception) {
                Log.e("KeeVoiceService", "initSpeechRecognizer failed: ${e.message}", e)
            }
        }
    }

    private fun initVoskWakeWord() {
        if (voskModel != null || isVoskLoading) return
        if (!KeeWakeWordModelManager.isModelReady(this)) {
            Log.w("KeeVoiceService", "Vosk wake-word model not found on disk; cannot start offline wake-word engine.")
            return
        }

        isVoskLoading = true
        Log.d("KeeVoiceService", "Loading Vosk offline wake-word model...")
        Thread {
            try {
                val modelDir = KeeWakeWordModelManager.getModelDir(this)
                val model = Model(modelDir.absolutePath)
                voskModel = model
                // Grammar-constrained recognizer restricted to primary wake phrase ("Hi Kee")
                val grammar = """["hi kee", "hi key", "[unk]"]"""
                val recognizer = Recognizer(model, 16000.0f, grammar)
                voskSpeechService = VoskSpeechService(recognizer, 16000.0f)
                isVoskLoading = false
                Log.i("KeeVoiceService", "Vosk wake-word model loaded successfully.")

                if (isRunning && !isPaused && !isOverlayShowing && isListeningForWakeWord) {
                    mainHandler.post { startWakeWordListening() }
                }
            } catch (e: Exception) {
                isVoskLoading = false
                Log.e("KeeVoiceService", "Failed to load Vosk wake-word model: ${e.message}", e)
            }
        }.start()
    }

    private val voskListener = object : VoskRecognitionListener {
        override fun onPartialResult(hypothesis: String?) {
            // Deliberately ignore partial results to prevent false activations from ambient speech.
        }

        override fun onResult(hypothesis: String?) {
            handleVoskHypothesis(hypothesis)
        }

        override fun onFinalResult(hypothesis: String?) {
            handleVoskHypothesis(hypothesis)
        }

        override fun onError(exception: Exception?) {
            Log.e("KeeVoiceService", "Vosk recognition error: ${exception?.message}", exception)
            isVoskListening = false
            scheduleVoskRecovery(isError = true)
        }

        override fun onTimeout() {
            Log.d("KeeVoiceService", "Vosk recognition timeout")
            isVoskListening = false
            scheduleVoskRecovery(isError = false)
        }
    }

    private fun scheduleVoskRecovery(isError: Boolean) {
        if (!isRunning || isPaused || isFlutterSessionActive || isOverlayShowing || isProcessingRequest || isSpeaking) {
            return
        }
        val delayMs = if (isError) {
            voskConsecutiveErrors = (voskConsecutiveErrors + 1).coerceAtMost(4)
            (1500L * (1 shl (voskConsecutiveErrors - 1))).coerceAtMost(15000L)
        } else {
            voskConsecutiveErrors = 0
            500L
        }
        restartListeningAfterDelay(delayMs)
    }

    private fun handleVoskHypothesis(hypothesis: String?) {
        if (!isListeningForWakeWord || isPaused || isOverlayShowing || isProcessingRequest || isSpeaking || hypothesis.isNullOrBlank()) {
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastWakeActivationMs < wakeCooldownMs) {
            return
        }
        try {
            val json = JSONObject(hypothesis)
            val raw = json.optString("text", "")
            val cleaned = raw.replace("[unk]", "").trim().lowercase(Locale.ROOT)
            if (cleaned.isEmpty()) return

            for (wakeWord in wakeWords) {
                val pattern = Regex("\\b${Regex.escape(wakeWord)}\\b")
                if (pattern.containsMatchIn(cleaned)) {
                    lastWakeActivationMs = now
                    Log.i("KeeVoiceService", "Confirmed final wake phrase detected: \"$wakeWord\"")
                    stopVoskListening()
                    triggerWakeWordDetected(cleaned, wakeWord)
                    return
                }
            }
        } catch (e: Exception) {
            Log.w("KeeVoiceService", "Failed to parse Vosk hypothesis: ${e.message}")
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
        if (isPaused || !isRunning || isOverlayShowing || isProcessingRequest || isSpeaking || isFlutterSessionActive) return
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
                if (!isVoskListening) {
                    Log.w("KeeVoiceService", "Vosk startListening returned false; scheduling recovery")
                    scheduleVoskRecovery(isError = true)
                } else {
                    voskConsecutiveErrors = 0
                }
            } catch (e: Exception) {
                isVoskListening = false
                Log.e("KeeVoiceService", "Vosk startListening failed: ${e.message}", e)
                scheduleVoskRecovery(isError = true)
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
            mainHandler.post {
                userRow?.visibility = View.VISIBLE
                tvUserTranscript?.text = "\"$text\""
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
        cancelAutoDismissOverlay()
        isOverlayCapturingSpeech = true
        lastFailureWasSpeech = false
        lastQuerySucceeded = false
        mainHandler.post {
            orbAnimView?.setState(OrbState.LISTENING)
            updateOverlayState("Listening...", "Speak")
            btnRetry?.visibility = View.GONE
            userRow?.visibility = View.VISIBLE
            tvUserTranscript?.text = "Speak naturally..."
            keeRow?.visibility = View.GONE
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        }

        mainHandler.postDelayed({
            if (!isRunning || !isOverlayShowing || isPaused) {
                isOverlayCapturingSpeech = false
                return@postDelayed
            }
            if (speechRecognizer == null) {
                initSpeechRecognizer()
                mainHandler.postDelayed({
                    if (!isRunning || !isOverlayShowing || isPaused) return@postDelayed
                    try {
                        isSpeechRecognizerActive = true
                        speechRecognizer?.startListening(intent)
                    } catch (e: Exception) {
                        isSpeechRecognizerActive = false
                        isOverlayCapturingSpeech = false
                        Log.e("KeeVoiceService", "startListening retry failed: ${e.message}", e)
                    }
                }, 150)
                return@postDelayed
            }
            try {
                if (isSpeechRecognizerActive) {
                    speechRecognizer?.cancel()
                    isSpeechRecognizerActive = false
                }
                isSpeechRecognizerActive = true
                speechRecognizer?.startListening(intent)
            } catch (e: Exception) {
                isSpeechRecognizerActive = false
                isOverlayCapturingSpeech = false
                Log.e("KeeVoiceService", "startListening failed: ${e.message}", e)
            }
        }, 350)
    }

    private fun retryLastRequest() {
        if (isProcessingRequest) return
        cancelAutoDismissOverlay()
        tts?.stop()
        isSpeaking = false

        if (lastFailureWasSpeech || lastUserQuery.isNullOrBlank()) {
            startListeningForUserQuery()
            return
        }
        if (lastQuerySucceeded) return
        val q = lastUserQuery ?: return
        processSpokenQuery(q)
    }

    private fun processSpokenQuery(query: String) {
        if (isProcessingRequest) return
        cancelAutoDismissOverlay()
        isOverlayCapturingSpeech = false
        isProcessingRequest = true
        lastUserQuery = query
        lastQuerySucceeded = false
        lastFailureWasSpeech = false

        mainHandler.post {
            orbAnimView?.setState(OrbState.THINKING)
            updateOverlayState("Thinking...", "Wait")
            btnRetry?.visibility = View.GONE
            userRow?.visibility = View.VISIBLE
            tvUserTranscript?.text = "\"$query\""
            keeRow?.visibility = View.GONE
            if (isSpeechRecognizerActive) {
                speechRecognizer?.stopListening()
                isSpeechRecognizerActive = false
            }
        }

        // Delegate query to Flutter's KeeConversationEngine if alive
        val handler = queryHandler
        if (handler != null) {
            var completed = false
            val timeoutRunnable = Runnable {
                if (!completed) {
                    completed = true
                    Log.w("KeeVoiceService", "queryHandler timed out for query: $query")
                    displayAndSpeakResponse(
                        "Kee took too long to respond. Tap Retry to try again.",
                        isError = true
                    )
                }
            }
            mainHandler.postDelayed(timeoutRunnable, 15000L)

            handler(query) { response ->
                mainHandler.post {
                    if (!completed) {
                        completed = true
                        mainHandler.removeCallbacks(timeoutRunnable)
                        val lower = response.lowercase(Locale.ROOT)
                        val isEngineError = lower.contains("couldn't process that request") ||
                            lower.contains("not connected right now")
                        displayAndSpeakResponse(response, isError = isEngineError)
                    }
                }
            }
        } else {
            Log.w("KeeVoiceService", "queryHandler unavailable for query: $query")
            val fallback = "Kee is not connected right now. Tap Retry or Open Kee."
            mainHandler.post {
                displayAndSpeakResponse(fallback, isError = true)
            }
        }
    }

    private fun displayAndSpeakResponse(reply: String, isError: Boolean = false) {
        isProcessingRequest = false
        lastQuerySucceeded = !isError
        mainHandler.post {
            keeRow?.visibility = View.VISIBLE
            tvKeeResponse?.text = reply
            tvKeeResponse?.setTextColor(
                Color.parseColor(if (isError) "#D97070" else "#F3F0E8")
            )
            btnRetry?.visibility = if (isError) View.VISIBLE else View.GONE
            if (isError) {
                orbAnimView?.setState(OrbState.ERROR)
                updateOverlayState("Request failed", "Speak")
            }
        }

        // Speak reply using native Android TTS when successful
        if (isTtsReady && tts != null && !isError) {
            val res = tts?.speak(reply, TextToSpeech.QUEUE_FLUSH, null, "KEE_REPLY")
            if (res == TextToSpeech.SUCCESS) {
                isSpeaking = true
                mainHandler.post {
                    orbAnimView?.setState(OrbState.SPEAKING)
                    updateOverlayState("Kee Speaking", "Interrupt")
                }
                return
            }
        }

        isSpeaking = false
        if (!isError) {
            mainHandler.post {
                orbAnimView?.setState(OrbState.IDLE)
                updateOverlayState("Tap orb to ask", "Speak")
                scheduleAutoDismissOverlay()
            }
        }
    }

    private fun updateOverlayState(statusText: String, micLabel: String) {
        tvStatus?.text = statusText
        btnActionMic?.text = micLabel
    }

    private fun handleSpeechError(error: Int) {
        if (isPaused || !isRunning) return

        if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            stopSelf()
            return
        }

        if (isListeningForWakeWord) {
            if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                consecutiveErrors = 0
                restartListeningAfterDelay(1500)
            } else {
                consecutiveErrors++
                val backoffMs = (2000L * (1 shl consecutiveErrors.coerceAtMost(3))).coerceAtMost(15000L)
                restartListeningAfterDelay(backoffMs)
            }
        } else {
            isOverlayCapturingSpeech = false
            lastFailureWasSpeech = true
            Log.w("KeeVoiceService", "Overlay SpeechRecognizer error code=$error")
            if (error == SpeechRecognizer.ERROR_CLIENT || error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) {
                // Recreate recognizer cleanly so Retry starts with a fresh instance
                initSpeechRecognizer()
            }
            mainHandler.post {
                if (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                    orbAnimView?.setState(OrbState.ERROR)
                    updateOverlayState("Didn't catch that", "Speak")
                    keeRow?.visibility = View.VISIBLE
                    tvKeeResponse?.text = "I didn't hear anything. Tap Retry to speak again."
                    tvKeeResponse?.setTextColor(Color.parseColor("#D8D2C5"))
                    btnRetry?.visibility = View.VISIBLE
                } else {
                    val reason = when (error) {
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                            "Network error during speech recognition. Tap Retry."
                        SpeechRecognizer.ERROR_AUDIO ->
                            "Microphone audio error. Tap Retry."
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                            "Speech service was busy. Tap Retry."
                        else ->
                            "Speech recognition failed (code $error). Tap Retry."
                    }
                    orbAnimView?.setState(OrbState.ERROR)
                    updateOverlayState("Voice error", "Speak")
                    keeRow?.visibility = View.VISIBLE
                    tvKeeResponse?.text = reason
                    tvKeeResponse?.setTextColor(Color.parseColor("#D97070"))
                    btnRetry?.visibility = View.VISIBLE
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
    // FLOATING SYSTEM OVERLAY — Holographic Orb + Compact Panel
    // ─────────────────────────────────────────────────────────────

    private fun getNavigationBarHeightPx(): Int {
        val resourceId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else dp(24)
    }

    private fun loadKeeLogoBitmap(): Bitmap? {
        return try {
            assets.open("flutter_assets/assets/logo/kee_logo_mark_dark.png").use { stream ->
                BitmapFactory.decodeStream(stream)
            }
        } catch (_: Exception) {
            null
        }
    }

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

        val cardWidth = (resources.displayMetrics.widthPixels * 0.94f).toInt()
        val params = WindowManager.LayoutParams(
            cardWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutParamsType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = getNavigationBarHeightPx() + dp(12)
        }

        overlayParams = params
        overlayView = createOverlayView()
        windowManager?.addView(overlayView, params)
        isOverlayShowing = true
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun createOverlayView(): View {
        // Transparent outer wrapper: primary floating holographic orb on top,
        // compact dark Kee-branded conversation panel underneath.
        val wrapper = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.TRANSPARENT)
        }

        // ── 1. Primary element: Floating Holographic Orb ───────────────────────
        orbAnimView = KeeHolographicOrbView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(96), dp(96)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(8)
            }
            setOnClickListener {
                when {
                    isSpeaking -> {
                        cancelAutoDismissOverlay()
                        tts?.stop()
                        isSpeaking = false
                        startListeningForUserQuery()
                    }
                    btnRetry?.visibility == View.VISIBLE -> retryLastRequest()
                    !isOverlayCapturingSpeech && !isProcessingRequest -> startListeningForUserQuery()
                    else -> dismissOverlay()
                }
            }
        }
        wrapper.addView(orbAnimView)

        // ── 2. Secondary element: Compact Bottom Conversation Panel ────────────
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setPadding(dp(14), dp(10), dp(14), dp(12))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F0080808"))
                cornerRadius = dp(22).toFloat()
                setStroke(dp(1), Color.parseColor("#38D8D2C5"))
            }
            elevation = dp(18).toFloat()
        }

        // Header: official Kee logo mark + status + Retry + Speak/Interrupt + Open Kee + Close
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val logoBitmap = loadKeeLogoBitmap()
        if (logoBitmap != null) {
            val ivLogo = ImageView(this).apply {
                setImageBitmap(logoBitmap)
                scaleType = ImageView.ScaleType.FIT_CENTER
                layoutParams = LinearLayout.LayoutParams(dp(22), dp(22)).apply {
                    marginEnd = dp(8)
                }
            }
            header.addView(ivLogo)
        }

        tvStatus = TextView(this).apply {
            text = "Listening..."
            setTextColor(Color.parseColor("#77736B"))
            textSize = 11.5f
            letterSpacing = 0.04f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        header.addView(tvStatus)

        // Retry pill (visible only when a request fails)
        btnRetry = TextView(this).apply {
            text = "Retry"
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#080808"))
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#D97070"))
                cornerRadius = dp(14).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginEnd = dp(6) }
            setOnClickListener { retryLastRequest() }
        }
        header.addView(btnRetry)

        // Speak / Interrupt pill
        btnActionMic = TextView(this).apply {
            text = "Speak"
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#080808"))
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#D8D2C5"))
                cornerRadius = dp(14).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginEnd = dp(6) }
            setOnClickListener {
                cancelAutoDismissOverlay()
                tts?.stop()
                isSpeaking = false
                isProcessingRequest = false
                startListeningForUserQuery()
            }
        }
        header.addView(btnActionMic)

        // Open Kee pill
        val btnOpenApp = TextView(this).apply {
            text = "Open Kee"
            textSize = 11f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#D8D2C5"))
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#141311"))
                cornerRadius = dp(14).toFloat()
                setStroke(1, Color.parseColor("#38D8D2C5"))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginEnd = dp(6) }
            setOnClickListener { launchFullApp() }
        }
        header.addView(btnOpenApp)

        // Close / minimize button
        val btnClose = TextView(this).apply {
            text = "✕"
            textSize = 12f
            setTextColor(Color.parseColor("#77736B"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(dp(24), dp(24))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#181715"))
            }
            setOnClickListener { dismissOverlay() }
        }
        header.addView(btnClose)
        panel.addView(header)

        // Subtle divider
        val divider = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1)
            ).apply {
                topMargin = dp(8)
                bottomMargin = dp(8)
            }
            setBackgroundColor(Color.parseColor("#242220"))
        }
        panel.addView(divider)

        // User row ("You" label + latest user transcription)
        val uRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(4) }
        }
        val tvYouLabel = TextView(this).apply {
            text = "You"
            setTextColor(Color.parseColor("#77736B"))
            textSize = 11.5f
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(dp(34), LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        uRow.addView(tvYouLabel)

        tvUserTranscript = TextView(this).apply {
            text = "Speak naturally..."
            setTextColor(Color.parseColor("#D8D2C5"))
            textSize = 13f
            setLineSpacing(dp(1).toFloat(), 1.15f)
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        uRow.addView(tvUserTranscript)
        userRow = uRow
        panel.addView(uRow)

        // Kee row ("Kee" label + latest Kee response)
        val kRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(2) }
        }
        val tvKeeLabel = TextView(this).apply {
            text = "Kee"
            setTextColor(Color.parseColor("#D8D2C5"))
            textSize = 11.5f
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(dp(34), LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        kRow.addView(tvKeeLabel)

        tvKeeResponse = TextView(this).apply {
            text = ""
            setTextColor(Color.parseColor("#F3F0E8"))
            textSize = 13.5f
            setLineSpacing(dp(2).toFloat(), 1.18f)
            maxLines = 4
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        kRow.addView(tvKeeResponse)
        keeRow = kRow
        panel.addView(kRow)

        wrapper.addView(panel)

        // Drag panel vertically to reposition over host apps
        var initialY = 0
        var initialTouchY = 0f
        panel.setOnTouchListener { _, event ->
            val p = overlayParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = p.y
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = (initialTouchY - event.rawY).toInt()
                    p.y = (initialY + dy).coerceIn(dp(16), resources.displayMetrics.heightPixels - dp(260))
                    windowManager?.updateViewLayout(wrapper, p)
                    true
                }
                else -> false
            }
        }

        return wrapper
    }

    private fun animateOrb(rmsdB: Float) {
        orbAnimView?.setListeningAmplitude(rmsdB)
    }

    private fun launchFullApp() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("route", "/ask-kee")
        }
        startActivity(launchIntent)
        dismissOverlay()
    }

    fun dismissOverlay(resumeWakeWord: Boolean = true) {
        val cleanupAndResume = Runnable {
            cancelAutoDismissOverlay()
            mainHandler.removeCallbacks(restartRunnable)

            if (overlayView != null && windowManager != null) {
                try {
                    windowManager?.removeView(overlayView)
                } catch (_: Exception) {}
                overlayView = null
                orbAnimView = null
                userRow = null
                tvUserTranscript = null
                keeRow = null
                tvKeeResponse = null
                tvStatus = null
                btnActionMic = null
                btnRetry = null
            }
            isOverlayShowing = false
            isOverlayCapturingSpeech = false

            // Interrupt TTS & cancel SpeechRecognizer synchronously on main thread
            // BEFORE restarting Vosk so the previous mic owner releases it first.
            tts?.stop()
            isSpeaking = false
            speechRecognizer?.cancel()

            if (resumeWakeWord && isRunning && !isPaused && !isFlutterSessionActive) {
                startWakeWordListening()
            }
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            cleanupAndResume.run()
        } else {
            mainHandler.post(cleanupAndResume)
        }
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
                    cancelAutoDismissOverlay()
                }
                override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                    mainHandler.post {
                        if (isSpeaking && isOverlayShowing) {
                            orbAnimView?.onTtsWordBoundary((end - start).coerceAtLeast(1))
                        }
                    }
                }
                override fun onDone(utteranceId: String?) {
                    isSpeaking = false
                    mainHandler.post {
                        if (isOverlayShowing && !isProcessingRequest && !isOverlayCapturingSpeech) {
                            orbAnimView?.setState(OrbState.IDLE)
                            updateOverlayState("Tap Speak to ask", "Speak")
                            scheduleAutoDismissOverlay()
                        }
                    }
                }
                override fun onError(utteranceId: String?) {
                    isSpeaking = false
                    mainHandler.post {
                        if (isOverlayShowing && !isProcessingRequest && !isOverlayCapturingSpeech) {
                            orbAnimView?.setState(OrbState.IDLE)
                            updateOverlayState("Tap Speak to ask", "Speak")
                            scheduleAutoDismissOverlay()
                        }
                    }
                }
            })
            isTtsReady = true
        } else {
            Log.e("KeeVoiceService", "TextToSpeech initialization failed with status: $status")
        }
    }

    override fun onDestroy() {
        Log.i("KeeVoiceService", "Destroying KeeBackgroundVoiceService")
        isRunning = false
        isPaused = true
        isFlutterSessionActive = false
        instance = null
        mainHandler.removeCallbacksAndMessages(null)
        stopVoskListening()
        try {
            voskSpeechService?.shutdown()
            voskModel?.close()
        } catch (_: Exception) {}
        dismissOverlay(resumeWakeWord = false)
        speechRecognizer?.destroy()
        tts?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
