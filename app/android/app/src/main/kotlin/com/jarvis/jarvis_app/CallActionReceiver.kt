package com.jarvis.jarvis_app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ANSWER     = "com.jarvis.jarvis_app.ACTION_ANSWER"
        const val ACTION_REJECT     = "com.jarvis.jarvis_app.ACTION_REJECT"
        const val EXTRA_CALLER      = "caller"
        const val EXTRA_ROOM_NAME   = "room_name"
        const val EXTRA_CALL_TYPE   = "call_type"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_ANSWER -> {
                Log.d("Jarvis", "Call action: ANSWER")
                IncomingCallService.stop(context)
                wakeUpScreen(context)

                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    putExtra("type", "incoming_call")
                    putExtra("action", "answer")
                    putExtra("caller",    intent.getStringExtra(EXTRA_CALLER)    ?: "Jarvis")
                    putExtra("room_name", intent.getStringExtra(EXTRA_ROOM_NAME) ?: "")
                    putExtra("call_type", intent.getStringExtra(EXTRA_CALL_TYPE) ?: "")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                context.startActivity(launchIntent)
            }
            ACTION_REJECT -> {
                Log.d("Jarvis", "Call action: REJECT")
                IncomingCallService.stop(context)
                // Also cancel the notification directly in case stop() didn't
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(IncomingCallService.NOTIFICATION_ID)
            }
        }
    }

    private fun wakeUpScreen(context: Context) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "Jarvis::CallAction"
            )
            wakeLock.acquire(5000L)
            wakeLock.release()
        } catch (e: Exception) {
            Log.e("Jarvis", "Error waking up screen", e)
        }
    }
}