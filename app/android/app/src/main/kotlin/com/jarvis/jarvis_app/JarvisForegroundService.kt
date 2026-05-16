package com.jarvis.jarvis_app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class JarvisForegroundService : Service() {

    override fun onCreate() {
        super.onCreate()
        Log.d("Jarvis", "Foreground service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, "jarvis_service")
            .setContentTitle("Jarvis")
            .setContentText("Active and ready")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()

        startForeground(2, notification)
        Log.d("Jarvis", "Foreground service running")

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d("Jarvis", "Foreground service destroyed")
    }
}
