import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import '../services/api_service.dart';
import '../utils/call_types.dart';
import '../widgets/verify_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;
  int _tasksDone = 0;
  int _tasksTotal = 0;
  String _lastCallStatus = '';

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
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    final data = await ApiService.getTodayData();
    if (!mounted) return;
    if (data != null) {
      final tasks = List<Map<String, dynamic>>.from(data['tasks'] ?? []);
      final done = tasks.where((t) {
        final d = t['done'];
        return d is bool ? d : d == true || d == 'true';
      }).length;
      setState(() {
        _tasksDone = done;
        _tasksTotal = tasks.length;
      });
    }
    final calls = await ApiService.getCallHistory(limit: 1);
    if (!mounted) return;
    if (calls.isNotEmpty) {
      final last = calls.first;
      final type = callTypeLabel(last['call_type']);
      final status = last['status'];
      final statusText = status == 'completed' ? 'Done' : (status ?? 'Unknown');
      setState(() => _lastCallStatus = '$type · $statusText');
    }
  }

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
        final roomName = message.data['room_name'] as String?;
        final callType = message.data['call_type'] as String?;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CallScreen(
            roomName: (roomName != null && roomName.isNotEmpty) ? roomName : null,
            callType: callType,
            autoAnswer: true,
          )),
        );
      }
    });
  }

  void _listenOpenedApp() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'incoming_call' && mounted) {
        final roomName = message.data['room_name'] as String?;
        final callType = message.data['call_type'] as String?;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => CallScreen(
            roomName: (roomName != null && roomName.isNotEmpty) ? roomName : null,
            callType: callType,
            autoAnswer: true,
          )),
          (_) => false,
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
                onTap: () async {
                  final verified = await showDialog<bool>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) => const VerifyDialog(),
                  );
                  if (verified == true && mounted) {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const CallScreen(callType: 'jarvis'),
                        transitionsBuilder: (_, a, __, child) =>
                            FadeTransition(opacity: a, child: child),
                        transitionDuration: const Duration(milliseconds: 500),
                      ),
                    );
                  }
                },
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
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatScreen(callType: 'jarvis')),
                  );
                },
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    border: Border.all(color: const Color(0xFF00E5FF), width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                        blurRadius: 12, spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.chat_bubble_outline, size: 24, color: Color(0xFF00E5FF)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'OR CHAT',
                style: TextStyle(
                  fontSize: 10, letterSpacing: 3,
                  color: Colors.cyanAccent.withValues(alpha: 0.3),
                ),
              ),
              if (_tasksTotal > 0 || _lastCallStatus.isNotEmpty) ...[
                const SizedBox(height: 24),
                if (_tasksTotal > 0)
                  Text(
                    '$_tasksDone/$_tasksTotal tasks done',
                    style: TextStyle(
                      fontSize: 13,
                      color: _tasksDone == _tasksTotal
                          ? const Color(0xFF00FF88)
                          : Colors.grey[500],
                    ),
                  ),
                if (_lastCallStatus.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _lastCallStatus,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
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
