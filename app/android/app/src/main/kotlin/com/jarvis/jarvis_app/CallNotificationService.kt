package com.jarvis.jarvis_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class CallNotificationService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "Jarvis"
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.data
        Log.d(TAG, "FCM received: $data")

        if (data["type"] != "incoming_call") return

        val caller   = data["caller"]    ?: "Jarvis"
        val roomName = data["room_name"] ?: ""
        val callType = data["call_type"] ?: ""

        try {
            postCallNotification(caller, roomName, callType)
            Log.d(TAG, "Call notification posted: room=$roomName type=$callType")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post notification from FCM", e)
        }

        IncomingCallService.start(this, caller)
        Log.d(TAG, "IncomingCallService start requested for call from $caller")
    }

    private fun postCallNotification(caller: String, roomName: String = "", callType: String = "") {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Ensure channel exists
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(IncomingCallService.CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    IncomingCallService.CHANNEL_ID,
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

        // Tapping the notification opens the app directly to the call screen
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("type", "incoming_call")
            putExtra("caller", caller)
            putExtra("room_name", roomName)
            putExtra("call_type", callType)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val fullScreenPi = PendingIntent.getActivity(
            this, 2, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, IncomingCallService.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Incoming call from $caller")
            .setContentText("Tap to answer")
            .setFullScreenIntent(fullScreenPi, true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)

        manager.notify(IncomingCallService.NOTIFICATION_ID, builder.build())
    }
}