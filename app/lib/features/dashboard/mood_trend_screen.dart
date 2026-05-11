import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class MoodTrendScreen extends StatefulWidget {
  final ApiClient api;
  const MoodTrendScreen({super.key, required this.api});

  @override
  State<MoodTrendScreen> createState() => _MoodTrendScreenState();
}

class _MoodTrendScreenState extends State<MoodTrendScreen> {
  List<dynamic> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.api.get('/api/v1/emotions?days=14');
    setState(() { _history = data['history'] ?? []; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(title: const Text('Mood Trends'), backgroundColor: const Color(0xFF1A1A1A)),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        itemBuilder: (context, i) {
          final e = _history[i];
          final mood = e['mood'] ?? 'neutral';
          final energy = (e['energy'] ?? 0.5) * 100;
          final stress = (e['stress'] ?? 0.5) * 100;
          final date = e['recorded_at']?.toString().split('T')[0] ?? '';

          return Card(
            color: const Color(0xFF1A1A1A),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: mood == 'motivated' ? Colors.green : mood == 'tired' ? Colors.orange : Colors.grey,
                child: Text(mood[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
              ),
              title: Text('$mood  $date'),
              subtitle: Text('Energy: ${energy.round()}%  Stress: ${stress.round()}%'),
            ),
          );
        },
      ),
    );
  }
}
