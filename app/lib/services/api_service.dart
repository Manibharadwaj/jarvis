import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiService {
  static const String _baseUrl = serverUrl;

  // Centralized headers — every backend call carries the X-App-Key that the
  // server checks via the appAuth middleware. If appApiKey is empty the call
  // will be rejected with 401; the user must rebuild the APK with
  // `--dart-define=APP_API_KEY=...`.
  static Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json',
        if (appApiKey.isNotEmpty) 'X-App-Key': appApiKey,
      };

  static Map<String, String> _headers() => {
        if (appApiKey.isNotEmpty) 'X-App-Key': appApiKey,
      };

  // Verify identity code for on-demand calls
  static Future<bool> verifyIdentity(String code) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/verify-identity'),
        headers: _jsonHeaders(),
        body: jsonEncode({'code': code}),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['verified'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // Start an ad-hoc voice call (no room name)
  static Future<Map<String, dynamic>?> startCall() async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/voice/start'),
        headers: _jsonHeaders(),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Join an existing scheduled call room
  static Future<Map<String, dynamic>?> joinCall(String roomName) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/voice/join'),
        headers: _jsonHeaders(),
        body: jsonEncode({'roomName': roomName}),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Get call history
  static Future<List<Map<String, dynamic>>> getCallHistory({int limit = 50, int offset = 0}) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/calls/history?limit=$limit&offset=$offset'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String, dynamic>>.from(data['calls'] ?? []);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // Get today's tasks and daily log
  static Future<Map<String, dynamic>?> getTodayData() async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/app/today'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Start a text chat session
  static Future<Map<String, dynamic>?> startChatSession(String callType, {String? roomName}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/chat/start'),
        headers: _jsonHeaders(),
        body: jsonEncode({'call_type': callType, if (roomName != null) 'room_name': roomName}),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) return jsonDecode(resp.body);
      return null;
    } catch (_) {
      return null;
    }
  }

  // Send a message in a chat session
  static Future<Map<String, dynamic>?> sendChatMessage(String sessionId, String message) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/chat/message'),
        headers: _jsonHeaders(),
        body: jsonEncode({'session_id': sessionId, 'message': message}),
      ).timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200) return jsonDecode(resp.body);
      return null;
    } catch (_) {
      return null;
    }
  }

  // End a chat session
  static Future<bool> endChatSession(String sessionId) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/chat/end'),
        headers: _jsonHeaders(),
        body: jsonEncode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Get chat transcript for a session
  static Future<List<Map<String, dynamic>>> getChatHistory(String sessionId) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/chat/history/$sessionId'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // Update a task from the app
  static Future<bool> updateTask(String id, Map<String, dynamic> updates) async {
    try {
      final resp = await http.patch(
        Uri.parse('$_baseUrl/api/app/task/$id'),
        headers: _jsonHeaders(),
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
