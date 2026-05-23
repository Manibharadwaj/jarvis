package com.jarvis.jarvis_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        var isInForeground = false
    }

    private var jarvisChannel: MethodChannel? = null
    private var fcmDataConsumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Volume buttons always control the ring stream so they work during incoming calls
        volumeControlStream = AudioManager.STREAM_RING
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
        promptFullScreenIntentPermission()
    }

    override fun onPause() {
        super.onPause()
        isInForeground = false
    }

    // On Android 14+, USE_FULL_SCREEN_INTENT requires explicit user approval.
    // Without it the call screen never appears over the lock screen.
    private fun promptFullScreenIntentPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.canUseFullScreenIntent()) return
        val prefs = getSharedPreferences("jarvis_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("fsi_prompted", false)) return
        prefs.edit().putBoolean("fsi_prompted", true).apply()
        try {
            val settingsIntent = Intent("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENTS")
            settingsIntent.data = Uri.parse("package:$packageName")
            settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(settingsIntent)
        } catch (e: Exception) {
            Log.e("Jarvis", "Could not open full-screen intent settings", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        jarvisChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarvis_fcm")
        jarvisChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getFcmData" -> {
                    val data = extractFcmData()
                    Log.d("Jarvis", "getFcmData: $data")
                    result.success(data)
                }
                "stopCallRingtone" -> {
                    IncomingCallService.stop(this)
                    result.success(true)
                }
                "startCallRingtone" -> {
                    val caller: String? = call.argument("caller")
                    IncomingCallService.start(this, caller ?: "Jarvis")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        createChannels()
        startForegroundService()
        AudioRouteChannel().start(flutterEngine, this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        this.intent = intent
        Log.d("Jarvis", "onNewIntent type=${intent.getStringExtra("type")} action=${intent.getStringExtra("action")}")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setTurnScreenOn(true)
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // Notify Flutter to show CallScreen when app is backgrounded
        if (intent.getStringExtra("type") == "incoming_call") {
            val caller   = intent.getStringExtra("caller")    ?: "Jarvis"
            val action   = intent.getStringExtra("action")    ?: ""
            val roomName = intent.getStringExtra("room_name") ?: ""
            val callType = intent.getStringExtra("call_type") ?: ""
            fcmDataConsumed = true
            jarvisChannel?.invokeMethod("incomingCall", mapOf(
                "caller" to caller, "action" to action,
                "room_name" to roomName, "call_type" to callType,
            ))
        }
    }

    override fun onWindowAttributesChanged(params: WindowManager.LayoutParams) {
        super.onWindowAttributesChanged(params)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setTurnScreenOn(true)
            setShowWhenLocked(true)
        }
    }

    private fun extractFcmData(): Map<String, String> {
        // Return empty after the first consumption so stale intent doesn't re-trigger
        if (fcmDataConsumed) return mapOf("__empty" to "true")
        val extras = intent?.extras ?: return mapOf("__empty" to "true")
        val data = mutableMapOf<String, String>()
        extras.keySet()?.forEach { key ->
            data[key] = extras.get(key)?.toString() ?: ""
        }
        if (data["type"] == "incoming_call") fcmDataConsumed = true
        return data
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (manager.getNotificationChannel(IncomingCallService.CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                IncomingCallService.CHANNEL_ID,
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming Jarvis AI calls"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                setShowBadge(true)
                enableLights(true)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
            Log.d("Jarvis", "Call channel created")
        }

        if (manager.getNotificationChannel("jarvis_service") == null) {
            val channel = NotificationChannel(
                "jarvis_service",
                "Jarvis Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Jarvis running in the background"
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
            Log.d("Jarvis", "Service channel created")
        }
    }

    private fun startForegroundService() {
        try {
            val intent = Intent(this, JarvisForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d("Jarvis", "Foreground service started")
        } catch (e: Exception) {
            Log.e("Jarvis", "Failed to start foreground service", e)
        }
    }
}