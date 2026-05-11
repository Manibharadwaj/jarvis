import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/home_screen.dart';
import 'features/notifications/notification_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisApp());
}

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Jarvis',
      theme: jarvisTheme,
      home: AuthGate(navKey: _navKey),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navKey;
  const AuthGate({super.key, required this.navKey});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final ApiClient api = ApiClient(AppConfig.apiBaseUrl);
  final NotificationHandler _notifHandler = NotificationHandler(ApiClient(AppConfig.apiBaseUrl));
  String? _token;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _restoreToken();
  }

  Future<void> _restoreToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('jwt_token');
    if (saved != null && saved.isNotEmpty) {
      api.setToken(saved);
      _notifHandler.api.setToken(saved);
      setState(() { _token = saved; _initialized = true; });
      _notifHandler.init();
    } else {
      setState(() => _initialized = true);
    }
  }

  void _onLogin(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    api.setToken(token);
    _notifHandler.api.setToken(token);
    _notifHandler.init();
    setState(() => _token = token);
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    setState(() => _token = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_token == null) {
      return LoginScreen(api: api, onLogin: _onLogin);
    }
    return HomeScreen(api: api, token: _token!, onLogout: _onLogout, notifHandler: _notifHandler);
  }
}
