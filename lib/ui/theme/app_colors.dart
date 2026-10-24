import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds - Bright, light theme as default
  static const Color background = Color(0xFFF8FAFC);       // Slate 50 clean light neutral
  static const Color surface = Color(0xFFFFFFFF);          // Crisp white
  static const Color surfaceElevated = Color(0xFFF1F5F9);  // Slate 100 subtle secondary fill
  static const Color surfaceGlass = Color(0xFFFFFFFF);     // Pure opaque white (no glassmorphism)
  static const Color border = Color(0xFFE2E8F0);           // Slate 200 crisp 1px border
  static const Color borderSubtle = Color(0xFFF1F5F9);     // Slate 100
  static const Color borderStrong = Color(0xFFCBD5E1);     // Slate 300
  static const Color borderGlow = Color(0xFFE2E8F0);

  // Restrained Accent: Single clean blue
  static const Color primary = Color(0xFF2563EB);          // Blue 600
  static const Color primaryDark = Color(0xFF1D4ED8);      // Blue 700
  static const Color primaryLight = Color(0xFFEFF6FF);     // Blue 50
  static const Color cyan = Color(0xFF2563EB);             // Mapped for compatibility
  static const Color electricBlue = Color(0xFF2563EB);     // Mapped for compatibility

  // Functional desktop status colors
  static const Color neutral = Color(0xFF475569);          // Slate 600
  static const Color neutralLight = Color(0xFFF8FAFC);     // Slate 50
  static const Color emerald = Color(0xFF16A34A);          // Green 600
  static const Color emeraldLight = Color(0xFFDCFCE7);     // Green 100
  static const Color amber = Color(0xFFD97706);            // Amber 600
  static const Color amberLight = Color(0xFFFEF3C7);       // Amber 100
  static const Color coral = Color(0xFFDC2626);            // Red 600
  static const Color coralLight = Color(0xFFFEE2E2);       // Red 100
  static const Color neonPurple = Color(0xFF475569);       // Mapped to dark slate

  // Linear Gradients - Subtle flat desktop gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF334155), Color(0xFF1E293B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF15803D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Text Colors - Charcoal & Dark Slate
  static const Color textPrimary = Color(0xFF0F172A);      // Slate 900 (Charcoal)
  static const Color textSecondary = Color(0xFF475569);    // Slate 600 (Dark Slate)
  static const Color textMuted = Color(0xFF64748B);        // Slate 500
  static const Color textAccent = Color(0xFF2563EB);       // Blue 600
}
