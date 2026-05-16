package com.jarvis.jarvis_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

class IncomingCallService : Service() {

    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "incoming_call_v3"
        private const val TAG = "Jarvis"

        private var mediaPlayer: MediaPlayer? = null
        private var wakeLock: PowerManager.WakeLock? = null
        private var audioFocusRequest: AudioFocusRequest? = null
        var isRunning = false
            private set
        @Volatile private var startRequested = false

        fun start(context: Context, caller: String) {
            synchronized(IncomingCallService::class.java) {
                if (isRunning || startRequested) {
                    Log.d(TAG, "IncomingCallService already running/requested, skipping")
                    return
                }
                startRequested = true
            }
            val intent = Intent(context, IncomingCallService::class.java).apply {
                putExtra("caller", caller)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "IncomingCallService start requested")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start IncomingCallService", e)
                startRequested = false  // Allow retry from another caller (e.g. foreground activity)
            }
        }

        fun stop(context: Context) {
            startRequested = false
            releaseAudioFocus(context)
            stopRingtone()
            releaseWakeLock()
            try {
                context.stopService(Intent(context, IncomingCallService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping service", e)
            }
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(NOTIFICATION_ID)
            } catch (e: Exception) {
                Log.e(TAG, "Error canceling notification", e)
            }
            isRunning = false
        }

        fun stopRingtone() {
            mediaPlayer?.let {
                try {
                    if (it.isPlaying) it.stop()
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping ringtone", e)
                }
                try {
                    it.release()
                } catch (e: Exception) {
                    Log.e(TAG, "Error releasing MediaPlayer", e)
                }
            }
            mediaPlayer = null
        }

        private fun releaseWakeLock() {
            wakeLock?.let {
                if (it.isHeld) {
                    try { it.release() } catch (e: Exception) { Log.e(TAG, "Error releasing wakeLock", e) }
                }
            }
            wakeLock = null
        }

        private fun releaseAudioFocus(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { req ->
                    try {
                        (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)
                            ?.abandonAudioFocusRequest(req)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error releasing audio focus", e)
                    }
                }
                audioFocusRequest = null
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "IncomingCallService onStartCommand")
        val caller = intent?.getStringExtra("caller") ?: "Jarvis"

        try {
            val notification = buildCallNotification(caller)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            isRunning = true
            acquireWakeLock()
            playRingtone()
            Log.d(TAG, "IncomingCallService started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error in IncomingCallService.onStartCommand", e)
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            // PARTIAL_WAKE_LOCK keeps CPU alive so MediaPlayer keeps playing even when
            // screen stays off. SCREEN_BRIGHT + ACQUIRE_CAUSES_WAKEUP turns screen on.
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "Jarvis::IncomingCall"
            )
            wakeLock?.acquire(60_000L)
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring wakeLock", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            // Sound is intentionally null — MediaPlayer handles the ringtone exclusively
            // so there's no double-ringtone from the notification channel + MediaPlayer.
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming Jarvis AI calls"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
                enableLights(true)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildCallNotification(caller: String): Notification {
        val answerIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_ANSWER
            putExtra(CallActionReceiver.EXTRA_CALLER, caller)
        }
        val answerPi = PendingIntent.getBroadcast(
            this, 0, answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val rejectIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_REJECT
        }
        val rejectPi = PendingIntent.getBroadcast(
            this, 1, rejectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("type", "incoming_call")
            putExtra("caller", caller)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val fullScreenPi = PendingIntent.getActivity(
            this, 2, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val callerPerson = Person.Builder().setName(caller).setImportant(true).build()

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setFullScreenIntent(fullScreenPi, true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(
                NotificationCompat.CallStyle.forIncomingCall(callerPerson, answerPi, rejectPi)
            )
        } else {
            builder.setContentTitle("Incoming call from $caller")
                .setContentText("Tap to answer")
                .addAction(NotificationCompat.Action.Builder(null, "Answer", answerPi).build())
                .addAction(NotificationCompat.Action.Builder(null, "Reject", rejectPi).build())
        }

        return builder.build()
    }

    private fun playRingtone() {
        try {
            val uri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (uri == null) {
                Log.e(TAG, "Default ringtone URI is null")
                return
            }

            val ringtoneAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(ringtoneAttrs)
                    .setAcceptsDelayedFocusGain(false)
                    .setWillPauseWhenDucked(false)
                    .build()
                audioFocusRequest = req
                audioManager.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    null, AudioManager.STREAM_RING, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                )
            }

            mediaPlayer = MediaPlayer().apply {
                setDataSource(this@IncomingCallService, uri)
                setAudioAttributes(ringtoneAttrs)
                isLooping = true
                prepare()
                start()
            }
            Log.d(TAG, "Ringtone playing via MediaPlayer")
        } catch (e: Exception) {
            Log.e(TAG, "MediaPlayer failed, trying Ringtone fallback", e)
            playRingtoneFallback()
        }
    }

    private fun playRingtoneFallback() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE) ?: return
            val ringtone = RingtoneManager.getRingtone(this, uri)
            ringtone.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone.play()
            Log.d(TAG, "Ringtone fallback playing")
        } catch (e: Exception) {
            Log.e(TAG, "All ringtone methods failed", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRingtone()
        releaseWakeLock()
        isRunning = false
        super.onDestroy()
    }
}