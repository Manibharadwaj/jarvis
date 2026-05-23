package com.jarvis.jarvis_app

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioRouteChannel : MethodChannel.MethodCallHandler {

    private var audioManager: AudioManager? = null

    fun start(flutterEngine: FlutterEngine, context: Context) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarvis_audio_route")
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val am = audioManager ?: return result.error("NO_AM", "AudioManager not available", null)
        when (call.method) {
            "setSpeaker" -> {
                val on = call.arguments as? Boolean ?: false
                am.isSpeakerphoneOn = on
                // MODE_IN_COMMUNICATION is best for VoIP calls
                // When speaker is on, use MODE_NORMAL for loud output
                // When earpiece, use MODE_IN_COMMUNICATION for proper audio routing
                am.mode = if (on) AudioManager.MODE_NORMAL else AudioManager.MODE_IN_COMMUNICATION
                result.success(true)
            }
            "isSpeakerOn" -> {
                result.success(am.isSpeakerphoneOn)
            }
            else -> result.notImplemented()
        }
    }
}