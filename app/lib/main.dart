import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'database/database_helper.dart';
import 'screens/shell_screen.dart';
import 'screens/call_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  // Init DB in background — it's lazy-safe, each query awaits internally
  DatabaseHelper.instance.database.ignore();

  // Handle incoming call when app is backgrounded: native sends this via onNewIntent
  const MethodChannel('jarvis_fcm').setMethodCallHandler((call) async {
    if (call.method == 'incomingCall') {
      final data       = Map<String, dynamic>.from(call.arguments as Map);
      final autoAnswer = data['action'] == 'answer';
      final roomName   = data['room_name'] as String? ?? '';
      final callType   = data['call_type'] as String?;
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => CallScreen(
          autoAnswer: autoAnswer,
          roomName: roomName.isNotEmpty ? roomName : null,
          callType: callType,
        )),
        (_) => false,
      );
    }
  });

  bool launchCall = false;
  bool autoAnswer = false;
  String? roomName;
  String? callType;

  try {
    final fcmData = await const MethodChannel('jarvis_fcm')
        .invokeMethod<Map>('getFcmData');
    if (fcmData?['type'] == 'incoming_call') {
      launchCall = true;
      autoAnswer = fcmData?['action'] == 'answer';
      final rn = fcmData?['room_name'] as String? ?? '';
      roomName = rn.isNotEmpty ? rn : null;
      callType = fcmData?['call_type'] as String?;
      const MethodChannel('jarvis_fcm')
          .invokeMethod('startCallRingtone', {'caller': 'Jarvis'});
    }
  } catch (_) {}

  runApp(JarvisApp(launchFromCall: launchCall, autoAnswer: autoAnswer, roomName: roomName, callType: callType));
}

class JarvisApp extends StatelessWidget {
  final bool launchFromCall;
  final bool autoAnswer;
  final String? roomName;
  final String? callType;
  const JarvisApp({super.key, this.launchFromCall = false, this.autoAnswer = false, this.roomName, this.callType});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E5FF),
        ),
      ),
      home: launchFromCall
          ? CallScreen(autoAnswer: autoAnswer, roomName: roomName, callType: callType)
          : const ShellScreen(),
    );
  }
}