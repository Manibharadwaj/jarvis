import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../features/voice/voice_call_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dashboard/mood_trend_screen.dart';
import '../../features/goals/goals_screen.dart';
import '../../features/planning/plan_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/notifications/notification_handler.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient api;
  final String token;
  final VoidCallback onLogout;
  final NotificationHandler notifHandler;
  const HomeScreen({super.key, required this.api, required this.token, required this.onLogout, required this.notifHandler});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.notifHandler.setOnStartCall(() {
      if (mounted) _startCall();
    });
  }

  Future<void> _startCall() async {
    try {
      final data = await widget.api.post('/api/v1/voice/start', {'call_type': 'check-in'});
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          api: widget.api,
          token: data['token'] as String,
          room: data['room'] as String,
          livekitUrl: data['url'] as String,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start call')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(api: widget.api),
      GoalsScreen(api: widget.api),
      ChatScreen(api: widget.api),
      PlanScreen(api: widget.api),
      MoodTrendScreen(api: widget.api),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Jarvis'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'Goals'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Plan'),
          BottomNavigationBarItem(icon: Icon(Icons.mood), label: 'Mood'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startCall,
        child: const Icon(Icons.call, color: Colors.black),
        backgroundColor: const Color(0xFF00E5FF),
      ),
    );
  }
}
