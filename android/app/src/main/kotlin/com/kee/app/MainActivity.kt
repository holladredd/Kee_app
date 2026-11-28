package com.kee.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
    private var methodChannel: MethodChannel? = null

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundListening" -> {
                    startVoiceService()
                    result.success(true)
                }
                "stopBackgroundListening" -> {
                    stopVoiceService()
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
                "pauseWakeWord" -> {
                    if (KeeBackgroundVoiceService.isRunning) {
                        val pauseIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
                            action = KeeBackgroundVoiceService.ACTION_PAUSE_LISTENING
                        }
                        startService(pauseIntent)
                    }
                    result.success(true)
                }
                "resumeWakeWord" -> {
                    if (KeeBackgroundVoiceService.isRunning && isHandsFreeEnabled()) {
                        val resumeIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
                            action = KeeBackgroundVoiceService.ACTION_RESUME_LISTENING
                        }
                        startService(resumeIntent)
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

    private fun startVoiceService() {
        setHandsFreeEnabled(true)
        val serviceIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
            action = KeeBackgroundVoiceService.ACTION_START_LISTENING
        }
        ContextCompat.startForegroundService(this, serviceIntent)
    }

    private fun stopVoiceService() {
        setHandsFreeEnabled(false)
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
        // Auto-start the background voice service when the app comes to foreground
        // if hands-free is enabled but the service is not yet running.
        // Do NOT pause Vosk here — microphone handover is now managed by
        // Flutter's pauseWakeWord/resumeWakeWord calls around speech sessions.
        if (isHandsFreeEnabled() && !KeeBackgroundVoiceService.isRunning) {
            startVoiceService()
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
        // Resume background wake-word detection whenever user leaves Kee if enabled once
        if (isHandsFreeEnabled()) {
            val resumeIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
                action = KeeBackgroundVoiceService.ACTION_RESUME_LISTENING
            }
            ContextCompat.startForegroundService(this, resumeIntent)
        }
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
}
