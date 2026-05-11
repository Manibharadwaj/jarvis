import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class GoalsScreen extends StatefulWidget {
  final ApiClient api;
  const GoalsScreen({super.key, required this.api});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<dynamic> _goals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.api.get('/api/v1/goals');
    setState(() { _goals = data['goals'] ?? []; _loading = false; });
  }

  Future<void> _create() async {
    final titleC = TextEditingController();
    final categoryC = TextEditingController();
    final freqC = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New Goal', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleC, decoration: _input('Title'), style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            TextField(controller: categoryC, decoration: _input('Category (e.g. health)'), style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            TextField(controller: freqC, decoration: _input('Frequency (e.g. daily)'), style: const TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (ok == true && titleC.text.isNotEmpty) {
      await widget.api.post('/api/v1/goals', {
        'title': titleC.text,
        'category': categoryC.text,
        'frequency': freqC.text,
      });
      _load();
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.api.delete('/api/v1/goals/$id');
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Goals'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _create),
        ],
      ),
      body: _goals.isEmpty
          ? const Center(child: Text('No goals yet. Tap + to add one.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _goals.length,
              itemBuilder: (_, i) {
                final g = _goals[i];
                return Card(
                  color: const Color(0xFF1A1A1A),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(g['title'] ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${g['category']}  Streak: ${g['streak']}', style: const TextStyle(color: Colors.grey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${(g['progress'] * 100).round()}%', style: const TextStyle(color: Color(0xFF00E5FF))),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => _delete(g['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF0D0D0D),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    );
  }
}
