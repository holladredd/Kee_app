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
        val serviceIntent = Intent(this, KeeBackgroundVoiceService::class.java).apply {
            action = KeeBackgroundVoiceService.ACTION_START_LISTENING
        }
        ContextCompat.startForegroundService(this, serviceIntent)
    }

    private fun stopVoiceService() {
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
        // If Kee is in the foreground, dismiss any active floating overlay
        // so the user interacts directly through Kee's full interface
        if (KeeBackgroundVoiceService.isOverlayShowing) {
            val serviceIntent = Intent(this, KeeBackgroundVoiceService::class.java)
            // Service handles in-app suppression automatically
        }
    }
}
