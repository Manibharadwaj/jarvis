import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final tasks = await _db.getTasksForDate(dateStr);
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _toggleTask(int id, String currentStatus) async {
    final newStatus = currentStatus == 'done' ? 'pending' : 'done';
    await _db.update('tasks', {'status': newStatus}, id);
    _load();
  }

  Future<void> _deleteTask(int id) async {
    await _db.delete('tasks', id);
    _load();
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final descController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('New Task',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'What do you need to do?',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Description (optional)',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00E5FF))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add',
                style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      await _db.insert('tasks', {
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'title': controller.text.trim(),
        'description': descController.text.trim(),
        'status': 'pending',
      });
      _load();
    }
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
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMM dd').format(_selectedDate);
    final isToday = _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.year == DateTime.now().year;

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
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00E5FF),
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.black),
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
              : ListView.builder(
                  padding: const EdgeInsets.only(
                      left: 16, right: 16, top: 16, bottom: 80),
                  itemCount: _tasks.length,
                  itemBuilder: (_, i) => _TaskCard(
                    task: _tasks[i],
                    onToggle: _toggleTask,
                    onDelete: _deleteTask,
                  ),
                ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final Function(int, String) onToggle;
  final Function(int) onDelete;

  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final id = task['id'] as int;
    final status = task['status'] as String;
    final done = status == 'done';
    final title = task['title'] as String;
    final desc = task['description'] as String? ?? '';
    final priority = (task['priority'] as num?)?.toInt() ?? 0;

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
            onPressed: () => onToggle(id, status),
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
                      decoration:
                          done ? TextDecoration.lineThrough : null,
                    )),
                if (desc.isNotEmpty)
                  Text(desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withValues(alpha: 0.6),
                      )),
              ],
            ),
          ),
          if (priority > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('P$priority',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.w600)),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Colors.redAccent),
            onPressed: () => onDelete(id),
          ),
        ],
      ),
    );
  }
}
