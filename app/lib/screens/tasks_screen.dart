import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../services/api_service.dart';
import '../config.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  bool _syncing = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final localTasks = await _db.getTasksForDate(dateStr);

    // Try to sync from backend for today
    if (_isToday()) {
      final remoteData = await ApiService.getTodayData();
      if (remoteData != null) {
        final remoteTasks = List<Map<String, dynamic>>.from(remoteData['tasks'] ?? []);
        if (remoteTasks.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _tasks = remoteTasks;
            _loading = false;
            _syncing = false;
          });
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _tasks = localTasks;
      _loading = false;
      _syncing = false;
    });
  }

  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.day == now.day &&
        _selectedDate.month == now.month &&
        _selectedDate.year == now.year;
  }

  Future<void> _toggleTask(dynamic id, bool currentDone) async {
    final newDone = !currentDone;
    setState(() {
      final idx = _tasks.indexWhere((t) => t['id'].toString() == id.toString());
      if (idx >= 0) _tasks[idx]['done'] = newDone;
    });

    // Try to update on backend (UUID ids from master_schedule)
    final success = await ApiService.updateTask(id.toString(), {'done': newDone});
    if (!success) {
      // Fallback to local DB
      final localId = id is int ? id : int.tryParse(id.toString()) ?? 0;
      if (localId > 0) {
        await _db.update('tasks', {'status': newDone ? 'done' : 'pending'}, localId);
      }
    }
  }

  Future<void> _deleteTask(dynamic id) async {
    setState(() {
      _tasks.removeWhere((t) => t['id'].toString() == id.toString());
    });
    // Note: no backend DELETE for app-side deletes; just remove from UI
  }

  Future<void> _refresh() async {
    setState(() => _syncing = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMM dd').format(_selectedDate);
    final isToday = _isToday();

    // Count completed/total from task data
    final doneCount = _tasks.where((t) {
      final done = t['done'];
      if (done is bool) return done;
      return done == true || done == 'true';
    }).length;
    final total = _tasks.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: GestureDetector(
          onTap: _pickDate,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isToday ? "Today's Tasks" : dateStr,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(width: 6),
              const Icon(Icons.edit_calendar,
                  size: 18, color: Color(0xFF00E5FF)),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00E5FF),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync, color: Color(0xFF00E5FF)),
              onPressed: _refresh,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text('No tasks for $dateStr',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (total > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              '$doneCount/$total done',
                              style: TextStyle(
                                fontSize: 13,
                                color: doneCount == total
                                    ? const Color(0xFF00FF88)
                                    : Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: total > 0 ? doneCount / total : 0,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  doneCount == total
                                      ? const Color(0xFF00FF88)
                                      : const Color(0xFF00E5FF),
                                ),
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        color: const Color(0xFF00E5FF),
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(
                              left: 16, right: 16, top: 4, bottom: 80),
                          itemCount: _tasks.length,
                          itemBuilder: (_, i) => _TaskCard(
                            task: _tasks[i],
                            onToggle: _toggleTask,
                            onDelete: _deleteTask,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _loading = true;
      });
      _load();
    }
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final Function(dynamic, bool) onToggle;
  final Function(dynamic) onDelete;

  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final id = task['id'];
    final doneVal = task['done'];
    final done = doneVal is bool ? doneVal : doneVal == true || doneVal == 'true';
    final title = (task['title'] ?? '') as String;
    final timeSlot = (task['time_slot'] ?? '') as String;
    final category = (task['category'] ?? 'other') as String;

    final categoryIcons = {
      'gym': Icons.fitness_center,
      'food': Icons.restaurant,
      'work': Icons.work,
      'code': Icons.code,
      'books': Icons.menu_book,
      'spiritual': Icons.self_improvement,
      'habits': Icons.repeat,
      'growth': Icons.trending_up,
      'personal': Icons.person,
      'other': Icons.circle,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: done ? 0.03 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? Colors.green : Colors.grey,
              size: 24,
            ),
            onPressed: () => onToggle(id, done),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: done ? Colors.grey : Colors.white,
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
                if (timeSlot.isNotEmpty || category != 'other')
                  Row(
                    children: [
                      if (timeSlot.isNotEmpty)
                        Text(timeSlot,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                      if (timeSlot.isNotEmpty && category != 'other')
                        Text(' · ', style: TextStyle(color: Colors.grey[700])),
                      if (category != 'other')
                        Text(category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                            )),
                    ],
                  ),
              ],
            ),
          ),
          Icon(
            categoryIcons[category] ?? Icons.circle,
            size: 16,
            color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}