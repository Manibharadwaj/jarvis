import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class DashboardScreen extends StatefulWidget {
  final ApiClient api;
  const DashboardScreen({super.key, required this.api});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.api.get('/api/v1/accountability');
    setState(() { _report = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final score = _report?['score'] ?? 0;
    final goals = _report?['goals'] as List? ?? [];
    final plans = _report?['plans'] as List? ?? [];
    final calls = _report?['calls'] as List? ?? [];

    final completedCalls = calls.where((c) => c['status'] == 'completed').length;
    final missedCalls = calls.where((c) => c['status'] == 'missed').length;
    final totalCalls = calls.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(title: const Text('Dashboard'), backgroundColor: const Color(0xFF1A1A1A)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ScoreCard(score: score),
          const SizedBox(height: 16),
          _StatRow(label: 'Goals', value: '${goals.length}'),
          _StatRow(label: 'Completed Calls', value: '$completedCalls'),
          _StatRow(label: 'Missed Calls', value: '$missedCalls'),
          _StatRow(label: 'Response Rate', value: totalCalls > 0 ? '${(completedCalls / totalCalls * 100).round()}%' : 'N/A'),
          const SizedBox(height: 24),
          const Text('Goals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...goals.map((g) => _GoalCard(goal: g)),
          const SizedBox(height: 16),
          const Text('Recent Days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...plans.map((p) => _PlanCard(plan: p)),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int score;
  const _ScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: score > 70 ? Colors.green : score > 40 ? Colors.orange : Colors.red38),
      ),
      child: Column(
        children: [
          Text('$score', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
          const Text('Accountability Score', style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label, value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: const TextStyle(fontSize: 16)), Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Map<String, dynamic> goal;
  const _GoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A1A),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(goal['title'] ?? ''),
        subtitle: Text('Streak: ${goal['streak']}  Progress: ${(goal['progress'] * 100).round()}%'),
        trailing: const Icon(Icons.check_circle, color: Color(0xFF00E5FF)),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A1A),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(plan['date']?.toString().split('T')[0] ?? ''),
        subtitle: Text(plan['evening_review'] ?? 'No review'),
      ),
    );
  }
}
