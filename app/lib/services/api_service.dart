import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiService {
  static const String _baseUrl = serverUrl;

  // Verify identity code for on-demand calls
  static Future<bool> verifyIdentity(String code) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/verify-identity'),
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Update a task from the app
  static Future<bool> updateTask(String id, Map<String, dynamic> updates) async {
    try {
      final resp = await http.patch(
        Uri.parse('$_baseUrl/api/app/task/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}