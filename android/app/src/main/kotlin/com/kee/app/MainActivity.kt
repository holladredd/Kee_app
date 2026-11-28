package com.kee.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.kee.app/voice_service"
    private val PREFS_NAME = "kee_voice_prefs"
    private val KEY_HANDS_FREE = "is_hands_free_enabled"
    private val KEY_HANDS_FREE_PROMPTED = "has_prompted_hands_free"
    private val REQ_CODE_VOICE_PERMS = 2002
    private var methodChannel: MethodChannel? = null
    private var isServiceStartPending = false
    private var pendingVoicePermissionResult: MethodChannel.Result? = null

    private fun isHandsFreeEnabled(): Boolean {
        return getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getBoolean(KEY_HANDS_FREE, true)
    }

    private fun setHandsFreeEnabled(enabled: Boolean) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HANDS_FREE, enabled)
            .apply()
    }

    private fun hasPromptedHandsFree(): Boolean {
        return getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getBoolean(KEY_HANDS_FREE_PROMPTED, false)
    }

    private fun setHandsFreePrompted(prompted: Boolean) {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_HANDS_FREE_PROMPTED, prompted)
            .apply()
    }

    private fun hasRecordAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundListening" -> {
                    setHandsFreeEnabled(true)
                    val started = startVoiceServiceIfEligible()
                    result.success(started)
                }
                "stopBackgroundListening" -> {
                    stopVoiceService()
                    result.success(true)
                }
                "isMicrophonePermissionGranted" -> {
                    result.success(hasRecordAudioPermission())
                }
                "requestVoicePermissions" -> {
                    requestVoicePermissions(result)
                }
                "hasPromptedHandsFree" -> {
                    result.success(hasPromptedHandsFree())
                }
                "setHandsFreePrompted" -> {
                    val prompted = call.argument<Boolean>("prompted") ?: true
                    setHandsFreePrompted(prompted)
                    result.success(true)
                }
                "isOverlayPermissionGranted" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(KeeBackgroundVoiceService.isRunning)
                }
                "getPersistedHandsFree" -> {
                    result.success(isHandsFreeEnabled())
                }
                "isWakeWordModelReady" -> {
                    result.success(KeeWakeWordModelManager.isModelReady(this))
                }
                "downloadWakeWordModel" -> {
                    KeeWakeWordModelManager.downloadAndExtract(
                        context = this,
                        onProgress = { pct ->
                            runOnUiThread {
                                methodChannel?.invokeMethod("modelDownloadProgress", mapOf("progress" to pct))
                            }
                        },
                        onComplete = { success, errorMsg ->
                            runOnUiThread {
                                if (success) {
                                    result.success(true)
                                } else {
                                    result.error("DOWNLOAD_FAILED", errorMsg ?: "Failed to download model", null)
                                }
                            }
                        }
                    )
                }
                "openApp" -> {
                    val appName = call.argument<String>("appName") ?: ""
                    result.success(openInstalledApp(appName))
                }
                "callContact" -> {
                    val target = call.argument<String>("target") ?: ""
                    result.success(callContactOrNumber(target))
                }
                "executeDeviceAction" -> {
                    val actionName = call.argument<String>("action") ?: ""
                    val params = call.argument<Map<String, Any?>>("params") ?: emptyMap()
                    result.success(executeDeviceAction(actionName, params))
                }
                "pauseWakeWord" -> {
                    KeeBackgroundVoiceService.isFlutterSessionActive = true
                    val service = KeeBackgroundVoiceService.instance
                    if (KeeBackgroundVoiceService.isRunning && service != null) {
                        service.pauseAndReleaseMic {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "resumeWakeWord" -> {
                    KeeBackgroundVoiceService.isFlutterSessionActive = false
                    val service = KeeBackgroundVoiceService.instance
                    if (KeeBackgroundVoiceService.isRunning && service != null && isHandsFreeEnabled()) {
                        service.resumeAfterFlutterSession()
                    } else if (isHandsFreeEnabled()) {
                        startVoiceServiceIfEligible()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Connect the background voice service to Kee's intelligence pipeline in Flutter
        KeeBackgroundVoiceService.queryHandler = { query, callback ->
            runOnUiThread {
                val channel = methodChannel
                if (channel == null) {
                    Log.w("KeeMainActivity", "MethodChannel unavailable for query: $query")
                    callback("Kee is not ready to process voice requests right now. Please try again.")
                    return@runOnUiThread
                }
                channel.invokeMethod("processQuery", mapOf("query" to query), object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val reply = result as? String
                        if (reply.isNullOrBlank()) {
                            Log.w("KeeMainActivity", "Empty reply from Flutter engine for query: $query")
                            callback("I couldn't process that request. Please try again.")
                        } else {
                            callback(reply)
                        }
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e("KeeMainActivity", "Flutter query error [$errorCode]: $errorMessage")
                        callback("I couldn't process that request. Please try again.")
                    }
                    override fun notImplemented() {
                        Log.e("KeeMainActivity", "processQuery not implemented on Flutter side")
                        callback("Kee is not ready to process voice requests right now. Please try again.")
                    }
                })
            }
        }
    }

    private fun requestVoicePermissions(result: MethodChannel.Result) {
        val needed = mutableListOf<String>()
        if (!hasRecordAudioPermission()) {
            needed.add(Manifest.permission.RECORD_AUDIO)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (needed.isEmpty()) {
            result.success(true)
            return
        }

        pendingVoicePermissionResult?.success(false)
        pendingVoicePermissionResult = result
        ActivityCompat.requestPermissions(this, needed.toTypedArray(), REQ_CODE_VOICE_PERMS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CODE_VOICE_PERMS) {
            pendingVoicePermissionResult?.success(hasRecordAudioPermission())
            pendingVoicePermissionResult = null
        }
    }

    private fun startVoiceServiceIfEligible(): Boolean {
        if (!isHandsFreeEnabled()) return false
        if (!hasRecordAudioPermission()) {
            Log.d("KeeMainActivity", "Skipping voice service start: RECORD_AUDIO not granted yet")
            return false
        }
        if (!KeeWakeWordModelManager.isModelReady(this)) {
            Log.d("KeeMainActivity", "Skipping voice service start: Vosk model not ready yet")
            return false
        }
        if (KeeBackgroundVoiceService.isRunning || isServiceStartPending) {
            return true
        }

        isServiceStartPending = true
        val serviceIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
            action = KeeBackgroundVoiceService.ACTION_START_LISTENING
        }
        try {
            ContextCompat.startForegroundService(this, serviceIntent)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                isServiceStartPending = false
            }, 2000L)
            return true
        } catch (e: Exception) {
            isServiceStartPending = false
            Log.e("KeeMainActivity", "Failed to start KeeBackgroundVoiceService: ${e.message}", e)
            return false
        }
    }

    private fun stopVoiceService() {
        isServiceStartPending = false
        setHandsFreeEnabled(false)
        KeeBackgroundVoiceService.isFlutterSessionActive = false
        val serviceIntent = Intent(this, KeeBackgroundVoiceService::class.java)
        stopService(serviceIntent)
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    override fun onResume() {
        super.onResume()
        // Authoritative startup path: auto-start background wake-word service
        // only when hands-free is enabled, RECORD_AUDIO is granted, and Vosk
        // model is ready. Does not pause Vosk on foreground entry.
        if (KeeBackgroundVoiceService.isRunning) {
            isServiceStartPending = false
            if (isHandsFreeEnabled() && !KeeBackgroundVoiceService.isFlutterSessionActive) {
                KeeBackgroundVoiceService.instance?.resumeAfterFlutterSession()
            }
        } else {
            startVoiceServiceIfEligible()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // When launched from floating overlay "Open Kee" button,
        // navigate to /ask-kee via Flutter's deep-link mechanism
        val route = intent.getStringExtra("route")
        if (route != null) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                methodChannel?.invokeMethod("navigateTo", mapOf("route" to route))
            }, 300)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Never restart Vosk while a Flutter voice session is still listening,
        // processing, or speaking.
        if (KeeBackgroundVoiceService.isFlutterSessionActive) {
            Log.d("KeeMainActivity", "onUserLeaveHint: Flutter voice session active, keeping Vosk paused")
            return
        }
        if (isHandsFreeEnabled()) {
            val service = KeeBackgroundVoiceService.instance
            if (KeeBackgroundVoiceService.isRunning && service != null) {
                service.resumeAfterFlutterSession()
            } else {
                startVoiceServiceIfEligible()
            }
        }
    }

    override fun onDestroy() {
        KeeBackgroundVoiceService.queryHandler = null
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }

    private fun openInstalledApp(rawName: String): Map<String, Any?> {
        val query = rawName.trim().lowercase()
        if (query.isEmpty()) {
            return mapOf("success" to false, "message" to "Please tell me which app to open.")
        }

        // Handle common natural aliases like "phone book"
        val normalizedTargets = when {
            query.contains("phone book") || query.contains("phonebook") || query.contains("contacts") ->
                listOf("contacts", "phone")
            query.contains("dialer") -> listOf("phone", "dialer")
            else -> listOf(query)
        }

        val pm = packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val apps = pm.queryIntentActivities(mainIntent, 0)

        var bestPkg: String? = null
        var bestLabel: String? = null

        for (target in normalizedTargets) {
            // 1. Exact label match
            for (info in apps) {
                val label = info.loadLabel(pm).toString()
                if (label.lowercase() == target) {
                    bestPkg = info.activityInfo.packageName
                    bestLabel = label
                    break
                }
            }
            if (bestPkg != null) break

            // 2. Partial label match
            for (info in apps) {
                val label = info.loadLabel(pm).toString()
                if (label.lowercase().contains(target) || target.contains(label.lowercase())) {
                    bestPkg = info.activityInfo.packageName
                    bestLabel = label
                    break
                }
            }
            if (bestPkg != null) break
        }

        if (bestPkg != null) {
            val launchIntent = pm.getLaunchIntentForPackage(bestPkg)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (launchIntent != null) {
                startActivity(launchIntent)
                return mapOf("success" to true, "message" to "Opening $bestLabel.")
            }
        }

        return mapOf("success" to false, "message" to "I couldn't find an app called \"$rawName\" on your device.")
    }

    private fun callContactOrNumber(rawTarget: String): Map<String, Any?> {
        val target = rawTarget.trim()
        if (target.isEmpty()) {
            return mapOf("success" to false, "message" to "Who would you like me to call?")
        }

        val digitsOnly = target.replace(Regex("[^0-9+]"), "")
        if (digitsOnly.length >= 3 && digitsOnly.count { it.isDigit() } == target.replace(Regex("[\\s\\-()+]"), "").length) {
            return placeOrDialNumber(digitsOnly, target)
        }

        // Look up in phone book (Contacts)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.CALL_PHONE), 2001)
            return mapOf(
                "success" to false,
                "message" to "Please allow Contacts permission so I can look up $target in your phone book, then ask me again."
            )
        }

        val cursor = contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            "LOWER(${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME}) LIKE ?",
            arrayOf("%${target.lowercase()}%"),
            null
        )

        cursor?.use {
            if (it.moveToFirst()) {
                val matchedName = it.getString(0) ?: target
                val matchedNumber = it.getString(1) ?: ""
                if (matchedNumber.isNotBlank()) {
                    return placeOrDialNumber(matchedNumber, matchedName)
                }
            }
        }

        return mapOf("success" to false, "message" to "I couldn't find \"$target\" in your contacts.")
    }

    private fun placeOrDialNumber(number: String, displayName: String): Map<String, Any?> {
        val hasCallPerm = ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
        val action = if (hasCallPerm) Intent.ACTION_CALL else Intent.ACTION_DIAL
        val intent = Intent(action, Uri.parse("tel:${Uri.encode(number)}")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        val verb = if (hasCallPerm) "Calling" else "Opening dialer for"
        return mapOf("success" to true, "message" to "$verb $displayName.")
    }

    private fun executeDeviceAction(action: String, params: Map<String, Any?>): Map<String, Any?> {
        return when (action) {
            "openApp" -> openInstalledApp(params["target"] as? String ?: "")
            "closeApp" -> {
                val appName = (params["target"] as? String ?: "that app").trim()
                mapOf(
                    "success" to false,
                    "supported" to false,
                    "message" to "I can't force-close $appName because Android doesn't allow assistant apps to close other apps without system or Accessibility permission. Say \"go home\" if you'd like to return to the home screen."
                )
            }
            "switchApp" -> {
                val target = (params["target"] as? String ?: "").trim()
                if (target.isEmpty()) {
                    mapOf(
                        "success" to false,
                        "supported" to false,
                        "message" to "Android doesn't allow opening the app switcher without Accessibility permission. Tell me which app you'd like to switch to and I'll open it."
                    )
                } else {
                    openInstalledApp(target)
                }
            }
            "callContact" -> callContactOrNumber(params["target"] as? String ?: "")
            "openDialer" -> openDialer()
            "recentCalls" -> openRecentCalls()
            "openMessages" -> openMessagesApp()
            "composeSms" -> composeSms(
                recipient = params["target"] as? String ?: "",
                body = params["body"] as? String ?: ""
            )
            "whatsappMessage" -> openWhatsAppMessage(
                target = params["target"] as? String ?: "",
                body = params["body"] as? String ?: ""
            )
            "setFlashlight" -> setFlashlight(params["enabled"] as? Boolean ?: true)
            "setAlarm" -> setAlarm(
                hour = (params["hour"] as? Number)?.toInt() ?: -1,
                minute = (params["minute"] as? Number)?.toInt() ?: 0,
                label = params["label"] as? String ?: "Kee Alarm"
            )
            "adjustVolume" -> adjustVolume(params["direction"] as? String ?: "up")
            "goHome" -> goHomeScreen()
            else -> mapOf(
                "success" to false,
                "supported" to false,
                "message" to "That device action isn't supported yet."
            )
        }
    }

    private fun openDialer(): Map<String, Any?> {
        return try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            mapOf("success" to true, "message" to "Opening the dialer.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't open the dialer on this device.")
        }
    }

    private fun openRecentCalls(): Map<String, Any?> {
        return try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            mapOf(
                "success" to true,
                "message" to "I don't have permission to read your call log directly, so I've opened the Phone app for your recent calls."
            )
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't open the Phone app to show recent calls.")
        }
    }

    private fun openMessagesApp(): Map<String, Any?> {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_APP_MESSAGING)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                mapOf("success" to true, "message" to "Opening Messages.")
            } else {
                openInstalledApp("messages")
            }
        } catch (e: Exception) {
            openInstalledApp("messages")
        }
    }

    private fun composeSms(recipient: String, body: String): Map<String, Any?> {
        return try {
            val cleanRecipient = recipient.trim()
            val uri = if (cleanRecipient.isNotEmpty() && cleanRecipient.any { it.isDigit() }) {
                Uri.parse("smsto:${Uri.encode(cleanRecipient.replace(Regex("[^0-9+]"), ""))}")
            } else {
                Uri.parse("smsto:")
            }
            val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (body.isNotBlank()) {
                    putExtra("sms_body", body)
                }
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                val targetDesc = if (cleanRecipient.isNotEmpty()) " for $cleanRecipient" else ""
                mapOf("success" to true, "message" to "Opening your SMS composer$targetDesc.")
            } else {
                mapOf("success" to false, "message" to "I couldn't find an SMS app on this device.")
            }
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't open the SMS composer.")
        }
    }

    private fun openWhatsAppMessage(target: String, body: String): Map<String, Any?> {
        val digits = target.replace(Regex("[^0-9+]"), "")
        if (digits.length >= 6) {
            return try {
                val encodedBody = if (body.isNotBlank()) "?text=${Uri.encode(body)}" else ""
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/${digits.removePrefix("+")}$encodedBody")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                mapOf("success" to true, "message" to "Opening a WhatsApp chat for $target. Tap send in WhatsApp when ready.")
            } catch (e: Exception) {
                openInstalledApp("whatsapp")
            }
        }
        val opened = openInstalledApp("whatsapp")
        return if (opened["success"] == true) {
            mapOf(
                "success" to true,
                "message" to "I've opened WhatsApp. Sending a WhatsApp message automatically without tapping send isn't supported."
            )
        } else {
            opened
        }
    }

    private fun setFlashlight(enabled: Boolean): Map<String, Any?> {
        return try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            var flashCameraId: String? = null
            for (id in cameraManager.cameraIdList) {
                val hasFlash = cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                if (hasFlash) {
                    flashCameraId = id
                    break
                }
            }
            if (flashCameraId == null) {
                return mapOf("success" to false, "message" to "This device doesn't appear to have a controllable flashlight.")
            }
            cameraManager.setTorchMode(flashCameraId, enabled)
            mapOf("success" to true, "message" to if (enabled) "Flashlight turned on." else "Flashlight turned off.")
        } catch (e: SecurityException) {
            mapOf("success" to false, "message" to "I don't have permission to control the flashlight right now.")
        } catch (e: CameraAccessException) {
            mapOf("success" to false, "message" to "The flashlight is currently unavailable because the camera is in use.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't change the flashlight state.")
        }
    }

    private fun setAlarm(hour: Int, minute: Int, label: String): Map<String, Any?> {
        if (hour !in 0..23 || minute !in 0..59) {
            return mapOf("success" to false, "message" to "Please tell me what time to set the alarm for.")
        }
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, label)
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                val formatted = String.format("%02d:%02d", hour, minute)
                mapOf("success" to true, "message" to "Setting an alarm for $formatted.")
            } else {
                mapOf("success" to false, "message" to "I couldn't find a clock app to set an alarm.")
            }
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't set that alarm.")
        }
    }

    private fun adjustVolume(direction: String): Map<String, Any?> {
        return try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (direction) {
                "up" -> {
                    audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                    mapOf("success" to true, "message" to "Volume turned up.")
                }
                "down" -> {
                    audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                    mapOf("success" to true, "message" to "Volume turned down.")
                }
                "mute" -> {
                    audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, AudioManager.FLAG_SHOW_UI)
                    mapOf("success" to true, "message" to "Media volume muted.")
                }
                "unmute" -> {
                    audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, AudioManager.FLAG_SHOW_UI)
                    mapOf("success" to true, "message" to "Media volume unmuted.")
                }
                else -> mapOf("success" to false, "message" to "Tell me whether to turn the volume up, down, or mute it.")
            }
        } catch (e: SecurityException) {
            mapOf("success" to false, "message" to "Do Not Disturb is preventing volume changes.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't adjust the volume.")
        }
    }

    private fun goHomeScreen(): Map<String, Any?> {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            mapOf("success" to true, "message" to "Returning to the home screen.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "I couldn't return to the home screen.")
        }
    }
}
