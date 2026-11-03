// Unused — retained for reference. See premium_background.dart for the active implementation.
import 'package:flutter/material.dart';

/// Animated full-screen gradient background.
///
/// Cycles through a small palette of brand-tinted color pairs on a ~16 s loop
/// so app screens never feel static, while staying subtle enough to keep the
/// monochrome brand palette and text readable. Rebuilding is cheap because the
/// app subtree is passed as [AnimatedBuilder.child] and never re-created.
class GradientBackground extends StatefulWidget {
  final Widget child;

  const GradientBackground({super.key, required this.child});

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const List<Color> _lightPalette = [
    Color(0xFFFDFDFD),
    Color(0xFFEFF2F7),
    Color(0xFFFDF8F6),
    Color(0xFFF1F6F1),
    Color(0xFFF6F4FA),
    Color(0xFFFDFDFD),
  ];

  static const List<Color> _darkPalette = [
    Color(0xFF0A0A0C),
    Color(0xFF12141B),
    Color(0xFF140F12),
    Color(0xFF0F1315),
    Color(0xFF111018),
    Color(0xFF0A0A0C),
  ];

  Color _lerpBetween(List<Color> palette, double t) {
    final n = palette.length;
    final scaled = t * (n - 1);
    final index = scaled.floor().clamp(0, n - 2);
    return Color.lerp(
      palette[index],
      palette[index + 1],
      scaled - index,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        final palette = isDark ? _darkPalette : _lightPalette;
        final top = _lerpBetween(palette, t);
        final bottom = _lerpBetween(palette, (t + 0.4) % 1.0);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
