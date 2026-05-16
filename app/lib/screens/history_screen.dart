import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import 'calendar_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _scores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scores = await _db.getAllScores();
    if (!mounted) return;
    setState(() {
      _scores = scores;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('My History',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Color(0xFF00E5FF)),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : _scores.isEmpty
              ? const Center(
                  child: Text('No data yet. Start your day with Jarvis!',
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _scores.length,
                  itemBuilder: (_, i) => _ScoreCard(score: _scores[i]),
                ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final Map<String, dynamic> score;
  const _ScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final date = score['date'] as String;
    final overall = (score['overall_score'] as num?)?.toDouble() ?? 0;
    final displayDate = _formatDate(date);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayDate,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 6),
                _metricRow('Gym', score['gym_score']),
                _metricRow('Timing', score['timing_score']),
                _metricRow('Tasks', score['task_score']),
                _metricRow('Food', score['food_score']),
              ],
            ),
          ),
          Column(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: overall / 100,
                      strokeWidth: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          overall >= 70
                              ? const Color(0xFF00E5FF)
                              : overall >= 40
                                  ? Colors.orangeAccent
                                  : Colors.redAccent),
                    ),
                    Text('${overall.toInt()}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text('SCORE',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, dynamic value) {
    final v = (value as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.withValues(alpha: 0.8))),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: v / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                  v >= 70
                      ? const Color(0xFF00E5FF)
                      : v >= 40
                          ? Colors.orangeAccent
                          : Colors.redAccent),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text('${v.toInt()}',
              style: const TextStyle(
                  fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  String _formatDate(String date) {
    try {
      final dt = DateTime.parse(date);
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      if (dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day) {
        return 'Today';
      } else if (dt.year == yesterday.year &&
          dt.month == yesterday.month &&
          dt.day == yesterday.day) {
        return 'Yesterday';
      }
      return DateFormat('MMM dd, yyyy').format(dt);
    } catch (_) {
      return date;
    }
  }
}
