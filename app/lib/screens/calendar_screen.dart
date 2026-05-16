import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _db = DatabaseHelper.instance;
  DateTime _currentMonth = DateTime.now();
  Map<String, double> _scoreMap = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scores = await _db.getMonthlyScores(
        _currentMonth.year, _currentMonth.month);
    final map = <String, double>{};
    for (final s in scores) {
      map[s['date'] as String] =
          (s['overall_score'] as num?)?.toDouble() ?? 0;
    }
    if (!mounted) return;
    setState(() => _scoreMap = map);
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Calendar',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Color(0xFF00E5FF)),
                  onPressed: _prevMonth,
                ),
                Text(monthLabel,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.chevron_right,
                      color: Color(0xFF00E5FF)),
                  onPressed: _nextMonth,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                ),
                itemCount: firstWeekday - 1 + daysInMonth,
                itemBuilder: (_, i) {
                  if (i < firstWeekday - 1) return const SizedBox();
                  final day = i - firstWeekday + 2;
                  final dateStr =
                      '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                  final score = _scoreMap[dateStr];
                  final isToday = today.year == _currentMonth.year &&
                      today.month == _currentMonth.month &&
                      today.day == day;

                  return GestureDetector(
                    onTap: score != null
                        ? () => _showDayDetail(dateStr, day, score)
                        : null,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: score != null
                            ? _scoreColor(score).withValues(alpha: 0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(
                                color: const Color(0xFF00E5FF), width: 1.5)
                            : null,
                      ),
                      child: Center(
                        child: Text('$day',
                            style: TextStyle(
                              fontSize: 13,
                              color: score != null
                                  ? Colors.white
                                  : Colors.grey,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w400,
                            )),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 70) return const Color(0xFF00E5FF);
    if (score >= 40) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  void _showDayDetail(String date, int day, double score) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('EEEE, MMM dd').format(DateTime.parse(date)),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            const SizedBox(height: 16),
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        _scoreColor(score)),
                  ),
                  Text('${score.toInt()}',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Daily Score',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
