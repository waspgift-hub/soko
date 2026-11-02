import 'package:flutter/material.dart';

/// Plain design tokens for the v2 UI. No gradients, shadows or illustrations.
class UiColors {
  UiColors._();

  static const Color ink = Color(0xFF111111);
  static const Color muted = Color(0xFF6B6B6B);
  static const Color line = Color(0xFFE5E5E5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFF7F7F7);
  static const Color accent = Color(0xFF0B7A3B);
  static const Color danger = Color(0xFFB42318);
  static const Color onAccent = Color(0xFFFFFFFF);
}

class UiSpace {
  UiSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
}

class UiRadius {
  UiRadius._();

  static const double control = 8;
}
