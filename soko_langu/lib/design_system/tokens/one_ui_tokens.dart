import 'package:flutter/material.dart';

class OneUiColors {
  OneUiColors._();

  // Core backgrounds
  static const Color background = Color(0xFFF6F6F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFF9F9F9);
  static const Color surfaceVariant = Color(0xFFF2F2F2);
  
  // Text
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF505050);
  static const Color textTertiary = Color(0xFF8E8E8E);
  static const Color textOnAccent = Color(0xFFFFFFFF);
  
  // Accent - Samsung style green
  static const Color accent = Color(0xFF1F8F4E);
  static const Color accentPressed = Color(0xFF197A42);
  static const Color accentContainer = Color(0xFFE8F5EE);
  
  // Borders & dividers
  static const Color border = Color(0xFFE5E5E5);
  static const Color divider = Color(0xFFF0F0F0);
  static const Color outline = Color(0xFFD0D0D0);
  
  // Semantic
  static const Color success = Color(0xFF1F8F4E);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);
  
  // Dark mode
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceContainer = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFAEAEB2);
  static const Color darkBorder = Color(0xFF38383A);
}

class OneUiSpacing {
  OneUiSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

class OneUiRadius {
  OneUiRadius._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double full = 999;
}

class OneUiElevation {
  OneUiElevation._();
  static const double none = 0;
  static const double sm = 2;
  static const double md = 4;
  static const double lg = 8;
}

class OneUiAnimation {
  OneUiAnimation._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration verySlow = Duration(milliseconds: 500);
  
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve spring = Curves.easeOutBack;
}
