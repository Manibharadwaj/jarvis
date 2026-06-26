import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const String serverUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'http://93.127.206.82:3000');
// Set at build time: `flutter build apk --dart-define=APP_API_KEY=...`.
// The key is baked into the APK and is required by every backend call.
const String appApiKey = String.fromEnvironment('APP_API_KEY', defaultValue: '0b2fce8d4fdf63a9fff1cf55981b77f7965083396d3d83e8ada2ea472281faba');
