import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 4),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );

    _initFcm();
    _listenOpenedApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  Future<void> _initFcm() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
      criticalAlert: true, provisional: false,
    );

    final token = await messaging.getToken();
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$serverUrl/api/register-token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token}),
        );
      } catch (_) {}
    }

    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'incoming_call' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CallScreen()),
        );
      }
    });
  }

  void _listenOpenedApp() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'incoming_call' && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CallScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/ironman.jpeg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Color(0xB0000015), BlendMode.srcOver,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, child) => Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset('assets/logo.jpg', fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF0088FF)],
                ).createShader(bounds),
                child: const Text(
                  'JARVIS',
                  style: TextStyle(
                    fontSize: 42, fontWeight: FontWeight.w900,
                    letterSpacing: 12, color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI ACCOUNTABILITY COMPANION',
                style: TextStyle(
                  fontSize: 11, letterSpacing: 4,
                  color: Colors.cyanAccent.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 60),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const CallScreen(),
                    transitionsBuilder: (_, a, __, child) =>
                        FadeTransition(opacity: a, child: child),
                    transitionDuration: const Duration(milliseconds: 500),
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (context, child) => Transform.scale(
                    scale: 1.0 + (math.sin(_animCtrl.value * 2 * math.pi) * 0.03),
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0055FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                            blurRadius: 25, spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.phone, size: 36, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'TAP TO ACTIVATE',
                style: TextStyle(
                  fontSize: 12, letterSpacing: 3,
                  color: Colors.cyanAccent.withValues(alpha: 0.4),
                ),
              ),
              const Spacer(),
              Text(
                'v1.1.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
