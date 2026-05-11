import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class ChatScreen extends StatefulWidget {
  final ApiClient api;
  const ChatScreen({super.key, required this.api});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgC = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _convId;
  bool _sending = false;

  Future<void> _send() async {
    final text = _msgC.text.trim();
    if (text.isEmpty) return;
    _msgC.clear();

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
    });

    try {
      final res = await widget.api.post('/api/v1/chat/message', {
        'message': text,
        if (_convId != null) 'conversation_id': _convId,
      });
      _convId = res['conversation_id'] as String?;
      setState(() {
        _messages.add({'role': 'assistant', 'content': res['reply'] as String});
        _sending = false;
      });
    } catch (e) {
      setState(() => _sending = false);
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _msgC.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(title: const Text('Chat with Jarvis'), backgroundColor: const Color(0xFF1A1A1A)),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Say hello to Jarvis', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isUser = m['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF00E5FF).withOpacity(0.2) : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            m['content'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Jarvis is typing...', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Color(0xFF1A1A1A)),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgC,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: const Color(0xFF0D0D0D),
                    ),
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send, color: Color(0xFF00E5FF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
