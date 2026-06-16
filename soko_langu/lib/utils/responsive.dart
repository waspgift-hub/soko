import 'dart:math';
import 'package:flutter/material.dart';

class Responsive {
  static double _width = 0;
  static double _height = 0;
  static double _topPadding = 0;
  static double _bottomPadding = 0;

  static void init(BuildContext context) {
    final media = MediaQuery.of(context);
    _width = media.size.width;
    _height = media.size.height;
    _topPadding = media.padding.top;
    _bottomPadding = media.padding.bottom;
  }

  static double wp(double percentage) => _width * (percentage / 100);
  static double hp(double percentage) => _height * (percentage / 100);
  static double sp(double size) => size * (_width / 375);
  static double get top => _topPadding;
  static double get bottom => _bottomPadding;
  static double get statusBar => _topPadding;
  static double get bottomBar => _bottomPadding;
  static bool get isLandscape => _width > _height;
  static bool get isSmallPhone => _width < 360;
  static bool get isTablet => _width >= 600;
  static bool get isDesktop => _width >= 900;

  static int gridColumns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return 5;
    if (w >= 900) return 4;
    if (w >= 600) return 3;
    return 2;
  }

  static int profileGridColumns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 900) return 5;
    if (w >= 600) return 4;
    return 3;
  }

  static double cardAspectRatio(BuildContext context) {
    final cols = gridColumns(context);
    if (cols >= 4) return 0.65;
    if (cols >= 3) return 0.68;
    return 0.72;
  }

  static double scaleFont(BuildContext context, double base) {
    final w = MediaQuery.of(context).size.width;
    return base * min(w / 375, 1.3);
  }
}

Widget safeAreaWrapper(Widget child) {
  return SafeArea(
    top: true,
    bottom: true,
    left: true,
    right: true,
    child: child,
  );
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;
  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        Responsive.init(context);
        return builder(context, constraints);
      },
    );
  }
}
