import 'package:flutter/material.dart';

/// Named motion tokens from the design system (§13).
class Motion {
  Motion._();

  static const Duration ripple = Duration(milliseconds: 200);
  static const Duration press = Duration(milliseconds: 100);
  static const Duration pressSpringBack = Duration(milliseconds: 300);
  static const Duration page = Duration(milliseconds: 350);
  static const Duration cardEnter = Duration(milliseconds: 300);
  static const Duration cardPress = Duration(milliseconds: 150);
  static const Duration sheet = Duration(milliseconds: 350);
  static const Duration hero = Duration(milliseconds: 450);
  static const Duration celebration = Duration(milliseconds: 900);
  static const Duration shimmerLoop = Duration(milliseconds: 1200);
  static const Duration snackbar = Duration(milliseconds: 250);
  static const Duration countUp = Duration(milliseconds: 800);

  static const Curve easeOutCubic = Curves.easeOutCubic;
  static const Curve easeInOutCubic = Curves.easeInOutCubic;
  static const Curve easeOutQuart = Curves.easeOutQuart;
  static const Curve overshootSpring = Curves.easeOutBack;
}
