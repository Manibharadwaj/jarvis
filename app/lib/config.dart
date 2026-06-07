import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const String serverUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'http://10.0.2.2:3000');
// Set at build time: `flutter build apk --dart-define=APP_API_KEY=...`.
// The key is baked into the APK and is required by every backend call.
const String appApiKey = String.fromEnvironment('APP_API_KEY', defaultValue: '');
