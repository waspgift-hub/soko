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

  /// Aspect ratio for product grids.
  ///
  /// Lower means taller. ProductCard renders four body rows (title, price,
  /// condition + district, rating + stock) instead of two, so the ratios are
  /// 0.62/0.60/0.58. The ratio is also divided by the user's text scale: at
  /// 1.3× those four rows need ~30% more vertical space, and without this the
  /// tile body overflowed for anyone using a larger system font.
  static double cardAspectRatio(BuildContext context) {
    final cols = gridColumns(context);
    final base = cols >= 4
        ? 0.58
        : cols >= 3
        ? 0.60
        : 0.62;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.35);
    return base / textScale;
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
