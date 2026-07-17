import 'dart:math';
import 'package:flutter/material.dart';

class PremiumBackground extends StatefulWidget {
  final Widget child;
  const PremiumBackground({super.key, required this.child});

  @override
  State<PremiumBackground> createState() => _PremiumBackgroundState();
}

class _PremiumBackgroundState extends State<PremiumBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _particles = <_Particle>[];
  final _glowSpots = <_GlowSpot>[];

  @override
  void initState() {
    super.initState();
    _initParticles();
    _initGlowSpots();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  void _initParticles() {
    final rng = Random(42);
    _particles.clear();
    for (var i = 0; i < 10; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 40 + rng.nextDouble() * 120,
        speed: 0.3 + rng.nextDouble() * 0.7,
        driftX: (rng.nextDouble() - 0.5) * 0.3,
        opacity: 0.04 + rng.nextDouble() * 0.08,
        delay: rng.nextDouble(),
      ));
    }
  }

  void _initGlowSpots() {
    final rng = Random(42);
    _glowSpots.clear();
    for (var i = 0; i < 3; i++) {
      _glowSpots.add(_GlowSpot(
        alignX: rng.nextDouble(),
        alignY: rng.nextDouble(),
        radius: 200 + rng.nextDouble() * 200,
        opacity: 0.08 + rng.nextDouble() * 0.1,
        pulseSpeed: 0.5 + rng.nextDouble() * 0.5,
        pulseDelay: rng.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Base gradient
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        cs.surface,
                        cs.surfaceContainerLow,
                        cs.surface,
                      ]
                    : [
                        cs.surface,
                        cs.surfaceContainerLow,
                        cs.surface,
                      ],
              ),
            ),
          ),
        ),
        // Glow spots — luminous light sources for glass reflection
        ...List.generate(_glowSpots.length, (i) {
          final spot = _glowSpots[i];
          return Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = (_controller.value + spot.pulseDelay) % 1.0;
                final pulse = 0.7 + 0.3 * sin(t * pi * 2 * spot.pulseSpeed);
                return IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(spot.alignX * 2 - 1, spot.alignY * 2 - 1),
                        radius: spot.radius / 600,
                        colors: [
                          cs.primary.withValues(alpha: spot.opacity * pulse),
                          cs.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }),
        // Floating particles
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _ParticlePainter(
                  particles: _particles,
                  progress: _controller.value,
                  color: isDark ? Colors.white : cs.primary,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
        // Main content
        widget.child,
      ],
    );
  }
}

class _GlowSpot {
  final double alignX;
  final double alignY;
  final double radius;
  final double opacity;
  final double pulseSpeed;
  final double pulseDelay;

  const _GlowSpot({
    required this.alignX,
    required this.alignY,
    required this.radius,
    required this.opacity,
    required this.pulseSpeed,
    required this.pulseDelay,
  });
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double driftX;
  final double opacity;
  final double delay;

  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.driftX,
    required this.opacity,
    required this.delay,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (progress + p.delay) % 1.0;
      final y = (p.y - t * p.speed) % 1.0;
      final x = (p.x + sin(t * pi * 2) * p.driftX) % 1.0;

      final cx = x * size.width;
      final cy = y * size.height;
      final r = p.size;

      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);

      canvas.drawOval(
        Rect.fromCircle(center: Offset(cx, cy), radius: r / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
