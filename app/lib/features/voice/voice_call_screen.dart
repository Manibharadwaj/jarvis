import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';

class VoiceCallScreen extends StatefulWidget {
  final ApiClient api;
  final String token;
  final String room;
  final String livekitUrl;

  const VoiceCallScreen({
    super.key,
    required this.api,
    required this.token,
    required this.room,
    required this.livekitUrl,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

enum CallState { connecting, connected, error, ended, timeout }

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  Room? _room;
  CallState _state = CallState.connecting;
  bool _muted = false;
  bool _speakerOn = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _state = CallState.connecting);

    try {
      final room = Room();

      Future.delayed(const Duration(seconds: 15), () {
        if (_state == CallState.connecting && mounted) {
          setState(() {
            _state = CallState.timeout;
            _errorMsg = 'Call timed out. LiveKit server may be unavailable.';
          });
          room.disconnect();
        }
      });

      await room.connect(
        widget.livekitUrl.isNotEmpty ? widget.livekitUrl : AppConfig.livekitUrl,
        widget.token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      await room.localParticipant?.setMicrophoneEnabled(true);

      if (!mounted) return;
      setState(() {
        _room = room;
        _state = CallState.connected;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = CallState.error;
        _errorMsg = 'Failed to connect: ${e.toString().replaceAll("Exception: ", "")}';
      });
    }
  }

  Future<void> _retry() async {
    await _room?.disconnect();
    _connect();
  }

  Future<void> _endCall() async {
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (mounted) setState(() => _state = CallState.ended);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _room?.localParticipant?.setMicrophoneEnabled(!_muted);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
  }

  @override
  void dispose() {
    _room?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 60,
                backgroundColor: Color(0xFF00E5FF),
                child: Icon(Icons.smart_toy, size: 60, color: Colors.black),
              ),
              const SizedBox(height: 24),
              const Text('Jarvis', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _statusWidget(),
              if (_state == CallState.error || _state == CallState.timeout) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(_errorMsg, style: const TextStyle(color: Colors.redAccent, fontSize: 14), textAlign: TextAlign.center),
                ),
              ],
              const SizedBox(height: 48),
              if (_state == CallState.connected) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _callButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      color: _muted ? Colors.red : Colors.white24,
                      onPressed: _toggleMute,
                    ),
                    const SizedBox(width: 24),
                    _callButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onPressed: _endCall,
                    ),
                    const SizedBox(width: 24),
                    _callButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                      color: Colors.white24,
                      onPressed: _toggleSpeaker,
                    ),
                  ],
                ),
              ],
              if (_state == CallState.connecting)
                _callButton(icon: Icons.call_end, color: Colors.red, onPressed: _endCall),
              if (_state == CallState.error || _state == CallState.timeout)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _callButton(icon: Icons.refresh, color: const Color(0xFF00E5FF), onPressed: _retry),
                    const SizedBox(width: 24),
                    _callButton(icon: Icons.close, color: Colors.grey, onPressed: _endCall),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusWidget() {
    switch (_state) {
      case CallState.connecting:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
            SizedBox(width: 8),
            Text('Connecting...', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        );
      case CallState.connected:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
          child: const Text('Connected', style: TextStyle(fontSize: 16, color: Colors.green)),
        );
      case CallState.error:
        return const Text('Connection failed', style: TextStyle(fontSize: 16, color: Colors.redAccent));
      case CallState.timeout:
        return const Text('Timed out', style: TextStyle(fontSize: 16, color: Colors.orange));
      case CallState.ended:
        return const Text('Call ended', style: TextStyle(fontSize: 16, color: Colors.grey));
    }
  }

  Widget _callButton({required IconData icon, required Color color, required VoidCallback onPressed}) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        iconSize: 32,
        minimumSize: const Size(64, 64),
      ),
    );
  }
}
