import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0A0D14);
  static const Color surface = Color(0xFF121824);
  static const Color surfaceElevated = Color(0xFF1A2234);
  static const Color surfaceGlass = Color(0x99162032);
  static const Color border = Color(0xFF25334D);
  static const Color borderGlow = Color(0x4000F0FF);

  // Accents & Gradients
  static const Color cyan = Color(0xFF00E5FF);
  static const Color electricBlue = Color(0xFF2979FF);
  static const Color neonPurple = Color(0xFF9D4EDD);
  static const Color emerald = Color(0xFF00E676);
  static const Color amber = Color(0xFFFFB300);
  static const Color coral = Color(0xFFFF5252);

  // Linear Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF9D4EDD), Color(0xFF00E5FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Text Colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textAccent = Color(0xFF38BDF8);
}
