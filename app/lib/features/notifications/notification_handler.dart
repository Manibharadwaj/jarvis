import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../voice/voice_call_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationHandler {
  final ApiClient api;

  NotificationHandler(this.api);

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token != null) {
      await api.post('/api/v1/notifications/register', {'fcm_token': token});
    }

    FirebaseMessaging.onMessage.listen((message) {
      // handled by system notification tray
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotification(message.data);
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _handleNotification(initial.data);
    }
  }

  void _handleNotification(Map<String, dynamic> data) {
    final callId = data['call_id'] as String?;
    final type = data['type'] as String?;

    if (callId != null && type == 'voice' && _onStartCall != null) {
      _onStartCall!();
    }
  }

  void Function()? _onStartCall;
  void setOnStartCall(void Function() cb) => _onStartCall = cb;
}
