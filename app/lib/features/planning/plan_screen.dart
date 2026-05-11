import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class PlanScreen extends StatefulWidget {
  final ApiClient api;
  const PlanScreen({super.key, required this.api});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  Map<String, dynamic>? _plan;
  final _intentC = TextEditingController();
  final _prioritiesC = TextEditingController();
  final _reviewC = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.get('/api/v1/plans/today');
      setState(() { _plan = data['plan']; _loading = false; });
      if (_plan != null) {
        _intentC.text = _plan!['morning_intent'] ?? '';
        _prioritiesC.text = (_plan!['priorities'] as List?)?.join(', ') ?? '';
        _reviewC.text = _plan!['evening_review'] ?? '';
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveMorning() async {
    final priorities = _prioritiesC.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    await widget.api.post('/api/v1/plans/morning', {
      'morning_intent': _intentC.text,
      'priorities': priorities,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Morning plan saved!')),
    );
    _load();
  }

  Future<void> _saveReview() async {
    await widget.api.post('/api/v1/plans/evening-review', {
      'review': _reviewC.text,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Evening review saved!')),
    );
    _load();
  }

  @override
  void dispose() {
    _intentC.dispose();
    _prioritiesC.dispose();
    _reviewC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(title: const Text('Daily Plan'), backgroundColor: const Color(0xFF1A1A1A)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Morning Intent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _intentC,
            decoration: _input("What's your focus today?"),
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _prioritiesC,
            decoration: _input("Priorities (comma-separated)"),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saveMorning,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            child: const Text('Save Morning Plan', style: TextStyle(color: Colors.black)),
          ),
          const SizedBox(height: 24),
          const Text('Evening Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _reviewC,
            decoration: _input("How did your day go?"),
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saveReview,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
            child: const Text('Save Evening Review', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  InputDecoration _input(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    );
  }
}
