import 'dart:math';
import 'package:flutter/material.dart';

/// Full-screen, multi-wave celebration rain: ~90 confetti pieces falling in
/// staggered bursts (a "sherehe" moment), painted without any package.
///
/// Use [CelebrationOverlay.show] to drop it over the whole UI and have it
/// auto-dismiss. Respects `MediaQuery.disableAnimations`.
class DsCelebrationRain extends StatefulWidget {
  final Duration duration;

  const DsCelebrationRain({super.key, this.duration = const Duration(milliseconds: 2600)});

  @override
  State<DsCelebrationRain> createState() => _DsCelebrationRainState();
}

class _DsCelebrationRainState extends State<DsCelebrationRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_RainParticle> _particles;

  static final Random _random = Random();

  static const _palette = [
    Color(0xFFFFD700),
    Color(0xFFFF6F00),
    Color(0xFF2D6A4F),
    Color(0xFFEC407A),
    Color(0xFF3D5AFE),
    Color(0xFF52B788),
    Color(0xFFFFB74D),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _particles = List.generate(90, (_) => _RainParticle.random());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return RepaintBoundary(
            child: CustomPaint(
              painter: _CelebrationRainPainter(
                particles: _particles,
                progress: _controller.value,
              ),
              size: Size.infinite,
            ),
          );
        },
      ),
    );
  }
}

/// Helper to drop a full-screen celebration over the current UI.
class CelebrationOverlay {
  static void show(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => const Positioned.fill(child: DsCelebrationRain()),
    );
    overlay.insert(entry);
    // one extra frame past the rain so the fade-out is never cut short
    Future.delayed(const Duration(milliseconds: 2800), () {
      entry.remove();
    });
  }
}

class _RainParticle {
  _RainParticle.random()
      : delay = _DsCelebrationRainState._random.nextDouble() * 0.55,
        x = _DsCelebrationRainState._random.nextDouble(),
        fallSpeed = 0.7 + _DsCelebrationRainState._random.nextDouble() * 0.6,
        size = 5 + _DsCelebrationRainState._random.nextDouble() * 5,
        spin = (_DsCelebrationRainState._random.nextDouble() - 0.5) * 8,
        color = _DsCelebrationRainState
            ._palette[_DsCelebrationRainState._random.nextInt(
              _DsCelebrationRainState._palette.length,
            )],
        isDot = _DsCelebrationRainState._random.nextBool();

  final double delay;
  final double x;
  final double fallSpeed;
  final double size;
  final double spin;
  final Color color;
  final bool isDot;
}

class _CelebrationRainPainter extends CustomPainter {
  final List<_RainParticle> particles;
  final double progress;

  _CelebrationRainPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // A piece takes ~1.2s of the 2.6s total to fall the full screen.
    const flight = 1.2;
    for (final p in particles) {
      final t = progress;
      final local = (t * 2.6 - p.delay) / flight;
      if (local <= 0 || local >= 1) continue;
      final eased = Curves.easeIn.transform(local);
      final opacity = (1 - local * 0.9).clamp(0.0, 1.0);
      final y = eased * (size.height + 40) - 20;
      final xPos = p.x * size.width;
      canvas.save();
      canvas.translate(xPos, y);
      canvas.rotate(p.spin * local);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      if (p.isDot) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.55,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationRainPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
