import 'package:flutter/material.dart';

final jarvisTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: const Color(0xFF00E5FF),
  scaffoldBackgroundColor: const Color(0xFF0D0D0D),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF00E5FF),
    secondary: Color(0xFF7C4DFF),
    surface: Color(0xFF1A1A1A),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    bodyLarge: TextStyle(fontSize: 16),
  ),
);
