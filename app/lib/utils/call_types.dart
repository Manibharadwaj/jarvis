import 'package:flutter/material.dart';

const callTypeLabels = {
  'wakeup': 'Wake Up',
  'night': 'Night Review',
  'jarvis': 'Manual Call',
  'manual': 'Manual Call',
};

const callTypeIcons = {
  'wakeup': Icons.alarm,
  'night': Icons.bedtime,
  'jarvis': Icons.phone,
  'manual': Icons.phone,
};

String callTypeLabel(String? type) =>
    callTypeLabels[type] ?? type?.replaceAll('-', ' ') ?? 'Unknown';

IconData callTypeIcon(String? type) =>
    callTypeIcons[type] ?? Icons.phone_in_talk;

Color callStatusColor(String? status) {
  switch (status) {
    case 'completed':
    case 'answered':
      return const Color(0xFF00FF88);
    case 'access_denied':
    case 'missed':
      return Colors.redAccent;
    case 'disconnected':
      return Colors.orangeAccent;
    case 'connected':
      return const Color(0xFF00E5FF);
    default:
      return Colors.grey;
  }
}

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '--';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m == 0) return '${s}s';
  return '${m}m ${s}s';
}

String formatCallTime(DateTime? time) {
  if (time == null) return '--';
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inDays == 0) return 'Today, ${time.hour}:${time.minute.toString().padLeft(2, "0")}';
  if (diff.inDays == 1) return 'Yesterday, ${time.hour}:${time.minute.toString().padLeft(2, "0")}';
  return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, "0")}';
}