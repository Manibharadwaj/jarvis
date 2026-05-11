import 'package:flutter/foundation.dart';

class AppConfig {
  static String get apiBaseUrl {
    const dev = 'http://localhost:3000';
    const prod = 'https://jarvis.yourdomain.com';
    return kReleaseMode ? prod : dev;
  }

  static String get livekitUrl {
    const dev = 'ws://localhost:7880';
    const prod = 'wss://jarvis.yourdomain.com/livekit';
    return kReleaseMode ? prod : dev;
  }
}
