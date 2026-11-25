package com.kee.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.kee.app/voice_service"
    private var methodChannel: MethodChannel? = null
    private var isHandsFreeEnabled = false

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
                else -> result.notImplemented()
            }
        }

        // Connect the background voice service to Kee's intelligence pipeline in Flutter
        KeeBackgroundVoiceService.queryHandler = { query, callback ->
            runOnUiThread {
                methodChannel?.invokeMethod("processQuery", mapOf("query" to query), object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        callback(result as? String ?: "I've noted that for you.")
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        callback("I've saved your note: $query.")
                    }
                    override fun notImplemented() {
                        callback("Noted: $query.")
                    }
                })
            }
        }
    }

    private fun startVoiceService() {
        isHandsFreeEnabled = true
        val serviceIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
            action = KeeBackgroundVoiceService.ACTION_START_LISTENING
        }
        ContextCompat.startForegroundService(this, serviceIntent)
    }

    private fun stopVoiceService() {
        isHandsFreeEnabled = false
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
        // While Kee is in the foreground, pause background wake-word mic access
        // so it doesn't collide with Kee's in-app voice assistant or spam the mic
        if (KeeBackgroundVoiceService.isRunning) {
            val pauseIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
                action = KeeBackgroundVoiceService.ACTION_PAUSE_LISTENING
            }
            startService(pauseIntent)
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
        // Only resume background wake-word detection when user explicitly enabled Hands-Free mode
        if (isHandsFreeEnabled) {
            val resumeIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
                action = KeeBackgroundVoiceService.ACTION_RESUME_LISTENING
            }
            ContextCompat.startForegroundService(this, resumeIntent)
        }
    }
}
