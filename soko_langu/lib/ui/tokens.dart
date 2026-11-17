import 'package:flutter/material.dart';
import '../theme/soko_palette.dart';

/// Plain design tokens for the v2 UI. No gradients, shadows or illustrations.
class UiColors {
  UiColors._();

  static const Color ink = SokoPalette.lightTextPrimary;
  static const Color muted = SokoPalette.lightTextSecondary;
  static const Color line = SokoPalette.lightBorder;
  static const Color surface = SokoPalette.lightCard;
  static const Color canvas = SokoPalette.lightBackground;
  static const Color accent = SokoPalette.lightPrimary;
  static const Color accentPressed = SokoPalette.lightPrimaryDark;
  static const Color accentContainer = SokoPalette.lightPrimaryLight;
  static const Color danger = SokoPalette.lightError;
  static const Color onAccent = SokoPalette.onLightPrimary;
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
