import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../utils/call_types.dart';

Map<String, String> _chatHeaders() => {
      'Content-Type': 'application/json',
      if (appApiKey.isNotEmpty) 'X-App-Key': appApiKey,
    };

class ChatScreen extends StatefulWidget {
  final String? callType;
  final String? roomName;

  const ChatScreen({super.key, this.callType, this.roomName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isLoading = false;
  bool _isEnded = false;
  String? _sessionId;
  String? _endReason;
  late final AnimationController _arcCtrl;

  @override
  void initState() {
    super.initState();
    _arcCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _startChat();
  }

  @override
  void dispose() {
    _arcCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _startChat() async {
    setState(() => _isLoading = true);
    try {
      final resp = await http.post(
        Uri.parse('$serverUrl/api/chat/start'),
        headers: _chatHeaders(),
        body: jsonEncode({
          'call_type': widget.callType ?? 'jarvis',
          if (widget.roomName != null) 'room_name': widget.roomName,
        }),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _sessionId = data['session_id'];
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', content: data['message'] ?? ''));
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        setState(() => _isLoading = false);
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      setState(() => _isLoading = false);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading || _isEnded || _sessionId == null) return;
    final msg = text.trim();
    _inputCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: msg));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final resp = await http.post(
        Uri.parse('$serverUrl/api/chat/message'),
        headers: _chatHeaders(),
        body: jsonEncode({'session_id': _sessionId, 'message': msg}),
      ).timeout(const Duration(seconds: 60));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', content: data['response'] ?? ''));
          _isLoading = false;
          if (data['is_ended'] == true) {
            _isEnded = true;
            _endReason = data['end_reason'];
          }
        });
        _scrollToBottom();
      } else {
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', content: 'Something went wrong. Try again.'));
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: 'Connection issue. Try again.'));
        _isLoading = false;
      });
    }
  }

  Future<void> _endChat() async {
    if (_sessionId == null) return;
    try {
      await http.post(
        Uri.parse('$serverUrl/api/chat/end'),
        headers: _chatHeaders(),
        body: jsonEncode({'session_id': _sessionId}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  void _scrollToBottom() {
    Future.microtask(() {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = callTypeLabel(widget.callType);
    final duration = _isEnded ? 'Ended' : 'Active';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && !_isEnded) _endChat();
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/tony.jpeg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Color(0xE0000015), BlendMode.srcOver),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Top bar ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        typeLabel.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          letterSpacing: 3,
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: _isEnded ? Colors.grey : const Color(0xFF00E5FF), width: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          duration,
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: _isEnded ? Colors.grey : const Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _isEnded ? () => Navigator.pop(context) : _endChat,
                        icon: const Icon(Icons.call_end, color: Colors.redAccent),
                        iconSize: 28,
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF00E5FF), height: 0.5, indent: 16, endIndent: 16),

                // ── Messages ──────────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isLoading) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: _ArcReactor(controller: _arcCtrl, size: 40)),
                        );
                      }
                      final msg = _messages[index];
                      final isAgent = msg.role == 'assistant';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Align(
                          alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0A1A).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(14),
                                topRight: const Radius.circular(14),
                                bottomLeft: Radius.circular(isAgent ? 2 : 14),
                                bottomRight: Radius.circular(isAgent ? 14 : 2),
                              ),
                              border: Border.all(
                                color: isAgent ? const Color(0xFF00E5FF) : const Color(0xFF00FF88),
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isAgent ? const Color(0xFF00E5FF) : const Color(0xFF00FF88)).withValues(alpha: 0.08),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              msg.content,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Ended banner ──────────────────────────────────────
                if (_isEnded)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0A0A1A),
                      border: Border(top: BorderSide(color: Color(0xFF00E5FF), width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _endReason == 'access_denied' ? Icons.lock : Icons.check_circle,
                          color: _endReason == 'access_denied' ? Colors.redAccent : const Color(0xFF00FF88),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _endReason == 'access_denied' ? 'Session ended — access denied' : 'Session complete',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close', style: TextStyle(color: Color(0xFF00E5FF))),
                        ),
                      ],
                    ),
                  ),

                // ── Input ──────────────────────────────────────────────
                if (!_isEnded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0A0A1A),
                      border: Border(top: BorderSide(color: Color(0xFF00E5FF), width: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            enabled: !_isLoading,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: _isLoading ? 'J.A.R.V.I.S. is thinking...' : 'Type a message...',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                              filled: true,
                              fillColor: const Color(0xFF111122),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 0.5),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 0.3),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 0.8),
                              ),
                            ),
                            onSubmitted: _sendMessage,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isLoading ? Colors.grey : const Color(0xFF00E5FF),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withValues(alpha: _isLoading ? 0 : 0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _isLoading ? null : () => _sendMessage(_inputCtrl.text),
                            icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String content;
  _ChatMessage({required this.role, required this.content});
}

// ── Arc Reactor spinner (matching call screen style) ─────────────────────────

class _ArcReactor extends StatelessWidget {
  final AnimationController controller;
  final double size;
  const _ArcReactor({required this.controller, this.size = 130});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(size, size),
          painter: _ArcPainter(controller.value),
        );
      },
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  _ArcPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    for (int i = 0; i < 4; i++) {
      final angle = progress * 2 * math.pi + (i * math.pi / 2);
      final paint = Paint()
        ..color = i.isEven ? const Color(0xFF00E5FF) : const Color(0xFF0055FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * (0.4 + i * 0.15)),
        angle,
        math.pi / 2.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.progress != progress;
}