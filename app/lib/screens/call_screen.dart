import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import '../config.dart';

enum CallState {
  ringing,
  connecting,
  connected,
  agentSpeaking,
  userSpeaking,
  ended,
  missed,
  error,
}

class CallScreen extends StatefulWidget {
  final bool autoAnswer;
  final String? roomName;
  const CallScreen({super.key, this.autoAnswer = false, this.roomName});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  CallState _state = CallState.ringing;
  String _statusDetail = '';

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _reactorCtrl;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _reactorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    if (widget.autoAnswer) {
      Future.microtask(_answer);
    } else {
      // Auto-decline after 12s if not answered
      Future.delayed(const Duration(seconds: 12), () {
        if (mounted && _state == CallState.ringing) _decline();
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _reactorCtrl.dispose();
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }

  void _stopRingtone() {
    const MethodChannel('jarvis_fcm').invokeMethod('stopCallRingtone');
  }

  Future<void> _answer() async {
    _stopRingtone();
    if (!mounted) return;
    setState(() {
      _state = CallState.connecting;
      _statusDetail = 'Connecting to J.A.R.V.I.S...';
    });

    try {
      // 1. Get LiveKit room token — join existing scheduled room or create a new one
      final http.Response resp;
      if (widget.roomName != null && widget.roomName!.isNotEmpty) {
        resp = await http
            .post(
              Uri.parse('$serverUrl/api/voice/join'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'roomName': widget.roomName}),
            )
            .timeout(const Duration(seconds: 15));
      } else {
        resp = await http
            .post(
              Uri.parse('$serverUrl/api/voice/start'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 15));
      }

      if (resp.statusCode != 200) {
        throw Exception('Backend error ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lkUrl = data['url'] as String;
      final token = data['token'] as String;

      // 2. Create LiveKit room
      _room = Room();
      _listener = _room!.createListener();

      _listener!
        ..on<RoomConnectedEvent>((_) {
          if (!mounted) return;
          setState(() {
            _state = CallState.connected;
            _statusDetail = 'Waiting for J.A.R.V.I.S...';
          });
        })
        ..on<ParticipantConnectedEvent>((e) {
          // Agent joined — Jarvis is ready
          if (!mounted) return;
          if (e.participant.identity != 'stark') {
            setState(() => _statusDetail = 'J.A.R.V.I.S. online');
          }
        })
        ..on<ActiveSpeakersChangedEvent>((e) {
          if (!mounted) return;
          final speakers = e.speakers;
          final agentSpeaking =
              speakers.any((p) => p.identity != 'stark');
          final userSpeaking =
              speakers.any((p) => p.identity == 'stark');

          if (agentSpeaking) {
            setState(() => _state = CallState.agentSpeaking);
          } else if (userSpeaking) {
            setState(() => _state = CallState.userSpeaking);
          } else if (_state == CallState.agentSpeaking ||
              _state == CallState.userSpeaking) {
            setState(() => _state = CallState.connected);
          }
        })
        ..on<RoomDisconnectedEvent>((_) {
          if (!mounted) return;
          setState(() => _state = CallState.ended);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        })
        ..on<TrackPublishedEvent>((e) {
          // Remote tracks (Jarvis audio) auto-play via LiveKit
        });

      // 3. Connect
      await _room!.connect(
        lkUrl,
        token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
        roomOptions: const RoomOptions(
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );

      // 4. Enable microphone
      await _room!.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = CallState.error;
        _statusDetail = 'Connection failed';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pop(context);
    }
  }

  void _decline() {
    _stopRingtone();
    if (!mounted) return;
    setState(() => _state = CallState.missed);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _hangUp() async {
    _stopRingtone();
    await _room?.disconnect();
    if (!mounted) return;
    setState(() => _state = CallState.ended);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.pop(context);
  }

  String get _statusText {
    switch (_state) {
      case CallState.ringing:
        return 'Incoming Call...';
      case CallState.connecting:
        return _statusDetail.isNotEmpty ? _statusDetail : 'Connecting...';
      case CallState.connected:
        return _statusDetail.isNotEmpty ? _statusDetail : 'Connected';
      case CallState.agentSpeaking:
        return 'J.A.R.V.I.S. Speaking';
      case CallState.userSpeaking:
        return 'Listening...';
      case CallState.ended:
        return 'Call Ended';
      case CallState.missed:
        return 'Call Missed';
      case CallState.error:
        return _statusDetail.isNotEmpty ? _statusDetail : 'Error';
    }
  }

  Color get _statusColor {
    switch (_state) {
      case CallState.ringing:
      case CallState.connecting:
      case CallState.connected:
        return const Color(0xFF00E5FF);
      case CallState.agentSpeaking:
        return const Color(0xFF00E5FF);
      case CallState.userSpeaking:
        return const Color(0xFF00FF88);
      case CallState.ended:
      case CallState.missed:
      case CallState.error:
        return Colors.grey;
    }
  }

  bool get _inCall =>
      _state == CallState.connected ||
      _state == CallState.agentSpeaking ||
      _state == CallState.userSpeaking;

  @override
  Widget build(BuildContext context) {
    final isRinging = _state == CallState.ringing;
    final isMissed = _state == CallState.missed;
    final isConnecting = _state == CallState.connecting;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/tony.jpeg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Color(0xB0000015),
              BlendMode.srcOver,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Avatar / reactor ──────────────────────────────────────
              if (isRinging)
                _PulsingLogo(anim: _pulseAnim)
              else
                _ArcReactor(
                  ctrl: _reactorCtrl,
                  color: _statusColor,
                  size: _inCall ? 130 : 100,
                ),

              const SizedBox(height: 24),

              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: [_statusColor, _statusColor.withValues(alpha: 0.6)],
                ).createShader(b),
                child: const Text(
                  'JARVIS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 16,
                    color: _statusColor,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                  ),
                ),
              ),

              // ── Connecting spinner ────────────────────────────────────
              if (isConnecting)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _statusColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),

              // ── Voice visualizer (user speaking) ─────────────────────
              if (_state == CallState.userSpeaking)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      final phase = _pulseCtrl.value;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final h =
                              8.0 + (math.sin(phase * 2 * math.pi - i * 1.2) + 1) * 12;
                          return Container(
                            width: 4,
                            height: h,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FF88),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00FF88)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),

              // ── Jarvis speaking wave ──────────────────────────────────
              if (_state == CallState.agentSpeaking)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: AnimatedBuilder(
                    animation: _reactorCtrl,
                    builder: (_, __) {
                      final phase = _reactorCtrl.value;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(7, (i) {
                          final h =
                              6.0 + (math.sin(phase * 2 * math.pi + i * 0.9) + 1) * 14;
                          return Container(
                            width: 3,
                            height: h,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),

              const Spacer(),

              // ── Buttons ───────────────────────────────────────────────
              if (isRinging)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallButton(
                        icon: Icons.call_end,
                        color: Colors.redAccent,
                        glowColor: Colors.redAccent,
                        onTap: _decline,
                      ),
                      const SizedBox(width: 80),
                      _CallButton(
                        icon: Icons.phone,
                        color: const Color(0xFF00FF88),
                        glowColor: const Color(0xFF00FF88),
                        onTap: _answer,
                      ),
                    ],
                  ),
                ),

              if (isMissed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Column(
                    children: [
                      Icon(Icons.call_missed,
                          size: 32,
                          color: Colors.redAccent.withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text('Call Missed',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                              letterSpacing: 1)),
                    ],
                  ),
                ),

              if (_inCall)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: _CallButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    glowColor: Colors.redAccent,
                    onTap: _hangUp,
                    size: 72,
                  ),
                ),

              if (_state == CallState.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off, size: 32, color: Colors.redAccent),
                      const SizedBox(height: 8),
                      Text(
                        _statusDetail,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _PulsingLogo extends StatelessWidget {
  final Animation<double> anim;
  const _PulsingLogo({required this.anim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Transform.scale(
        scale: anim.value,
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset('assets/logo.jpg', fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _ArcReactor extends StatelessWidget {
  final AnimationController ctrl;
  final Color color;
  final double size;
  const _ArcReactor(
      {required this.ctrl, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ArcReactorPainter(progress: ctrl.value, color: color),
          child: Center(
            child: ClipOval(
              child: Image.asset(
                'assets/logo.jpg',
                width: size * 0.28,
                height: size * 0.28,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcReactorPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _ArcReactorPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final rp = (progress + i / 3) % 1.0;
      final rr = radius * (0.2 + rp * 0.6);
      canvas.drawCircle(
        center,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = color.withValues(alpha: (1.0 - rp) * 0.3),
      );
    }

    canvas.drawCircle(
        center, radius * 0.08, Paint()..color = color);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.85),
      progress * 2 * math.pi,
      0.3 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.65),
      progress * 2 * math.pi + math.pi,
      0.2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.4)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcReactorPainter old) => old.progress != progress;
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color glowColor;
  final VoidCallback onTap;
  final double size;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.glowColor,
    required this.onTap,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.3),
              blurRadius: 15,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.44),
      ),
    );
  }
}
