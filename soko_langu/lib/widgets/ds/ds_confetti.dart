import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';

/// One-shot confetti burst (spec §15.8): ~40 emerald/gold/amber particles
/// with gravity and fade, painted without any third-party package.
class DsConfetti extends StatefulWidget {
  final int particleCount;
  final Duration duration;

  const DsConfetti({
    super.key,
    this.particleCount = 40,
    this.duration = Motion.celebration,
  });

  @override
  State<DsConfetti> createState() => _DsConfettiState();
}

class _DsConfettiState extends State<DsConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  static final Random _random = Random();

  static const _palette = [
    Color(0xFF2D6A4F),
    Color(0xFFFFD700),
    Color(0xFFFFB74D),
    Color(0xFF52B788),
    Color(0xFFFF6F00),
  ];

  @override
  void initState() {
    super.initState();
    _particles = List.generate(widget.particleCount, (_) => _Particle.random());
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle.random()
      : angle = _DsConfettiState._random.nextDouble() * 2 * pi,
        speed = 180 + _DsConfettiState._random.nextDouble() * 320,
        size = 3 + _DsConfettiState._random.nextDouble() * 4,
        color = _DsConfettiState
            ._palette[_DsConfettiState._random.nextInt(
              _DsConfettiState._palette.length,
            )],
        spin = (_DsConfettiState._random.nextDouble() - 0.5) * 6;

  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;

  double x(double t) => cos(angle) * speed * t;
  double y(double t) => sin(angle) * speed * t + 340 * t * t;
  double rotation(double t) => spin * t;
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.35);
    for (final p in particles) {
      final t = progress;
      final opacity = (1 - t).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      final pos = center + Offset(p.x(t), p.y(t));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.rotation(t));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = p.color.withValues(alpha: opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
