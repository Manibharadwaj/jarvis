import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const String serverUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'http://10.0.2.2:3000');
