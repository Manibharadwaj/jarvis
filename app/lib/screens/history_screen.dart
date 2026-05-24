import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import '../utils/call_types.dart';
import 'calendar_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _scores = [];
  List<Map<String, dynamic>> _calls = [];
  bool _scoresLoading = true;
  bool _callsLoading = true;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index != _currentTab) {
        setState(() => _currentTab = _tabCtrl.index);
      }
    });
    _loadScores();
    _loadCalls();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadScores() async {
    final scores = await _db.getAllScores();
    if (!mounted) return;
    setState(() {
      _scores = scores;
      _scoresLoading = false;
    });
  }

  Future<void> _loadCalls() async {
    final calls = await ApiService.getCallHistory();
    if (!mounted) return;
    setState(() {
      _calls = calls;
      _callsLoading = false;
    });
  }

  Future<void> _refresh() async {
    if (_currentTab == 0) {
      setState(() => _callsLoading = true);
      await _loadCalls();
    } else {
      setState(() => _scoresLoading = true);
      await _loadScores();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('History',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month, color: Color(0xFF00E5FF)),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'CALLS'),
            Tab(text: 'SCORES'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _callsLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              : _calls.isEmpty
                  ? Center(
                      child: Text('No calls yet.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16)))
                  : RefreshIndicator(
                      color: const Color(0xFF00E5FF),
                      onRefresh: _refresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _calls.length,
                        itemBuilder: (_, i) => _CallCard(call: _calls[i]),
                      ),
                    ),
          _scoresLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
              : _scores.isEmpty
                  ? Center(
                      child: Text('No scores yet.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _scores.length,
                      itemBuilder: (_, i) => _ScoreCard(score: _scores[i]),
                    ),
        ],
      ),
    );
  }
}

// ─── Call History Card ──────────────────────────────────────────────────────

class _CallCard extends StatelessWidget {
  final Map<String, dynamic> call;
  const _CallCard({required this.call});

  @override
  Widget build(BuildContext context) {
    final type = call['call_type'] as String?;
    final status = call['status'] as String?;
    final startedAt = call['started_at'] as String?;
    final duration = call['duration_seconds'] as int?;
    final summary = call['summary'] as String?;
    final verified = call['identity_verified'] as bool?;

    DateTime? time;
    if (startedAt != null) {
      time = DateTime.tryParse(startedAt);
    }

    final statusCol = callStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusCol.withValues(alpha: 0.15),
            ),
            child: Icon(callTypeIcon(type), color: statusCol, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      callTypeLabel(type),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: statusCol.withValues(alpha: 0.2),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(fontSize: 10, color: statusCol, letterSpacing: 1),
                      ),
                    ),
                    if (verified == true) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 14, color: Color(0xFF00E5FF)),
                    ],
                    if (call['medium'] == 'text') ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.chat_bubble, size: 14, color: Color(0xFF00E5FF)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(time),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.timer, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      formatDuration(duration),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
                if (summary != null && summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    summary.length > 80 ? '${summary.substring(0, 80)}...' : summary,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String? status) {
    final isText = call['medium'] == 'text';
    switch (status) {
      case 'completed': return isText ? 'CHAT' : 'DONE';
      case 'access_denied': return 'DENIED';
      case 'disconnected': return 'CUT';
      case 'missed': return 'MISSED';
      case 'connected': return isText ? 'LIVE' : 'LIVE';
      default: return (status ?? 'UNKNOWN').toUpperCase();
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0) return 'Today, ${time.hour}:${time.minute.toString().padLeft(2, "0")}';
    if (diff.inDays == 1) return 'Yesterday';
    return '${time.day}/${time.month}';
  }
}

// ─── Score Card (kept from original) ─────────────────────────────────────────

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