import 'dart:math';
import 'package:flutter/material.dart';

/// Decorative aurora background that stays static unless animation is opted in.
class PremiumBackground extends StatelessWidget {
  final Widget child;
  final bool animate;

  const PremiumBackground({
    super.key,
    required this.child,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: _AuroraPanels(
              animate: animate && !MediaQuery.disableAnimationsOf(context),
              child: const _AuroraRender(),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _AuroraPanels extends StatefulWidget {
  final Widget child;
  final bool animate;

  const _AuroraPanels({required this.child, required this.animate});

  @override
  State<_AuroraPanels> createState() => _AuroraPanelsState();
}

class _AuroraPanelsState extends State<_AuroraPanels>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 35),
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return _AuroraProgress(value: 0, child: widget.child);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return _AuroraProgress(value: _ctrl.value, child: widget.child);
      },
    );
  }
}

class _AuroraProgress extends InheritedWidget {
  final double value;
  const _AuroraProgress({
    required this.value,
    required super.child,
  });

  static double of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AuroraProgress>()!.value;
  }

  @override
  bool updateShouldNotify(_AuroraProgress old) => old.value != value;
}

class _AuroraRender extends StatelessWidget {
  const _AuroraRender();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AuroraPainter(context: context),
      size: Size.infinite,
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final BuildContext context;

  _AuroraPainter({required this.context});

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  ColorScheme get _cs => Theme.of(context).colorScheme;
  late final double _progress = _AuroraProgress.of(context);

  static final _blobs = List<_Blob>.generate(4, (i) {
    final rng = Random(42 + i);
    return _Blob(
      nx: rng.nextDouble(),
      ny: rng.nextDouble(),
      radius: 180 + rng.nextDouble() * 220,
      speed: 0.08 + rng.nextDouble() * 0.12,
      driftX: (rng.nextDouble() - 0.5) * 0.15,
      driftY: (rng.nextDouble() - 0.5) * 0.10,
      opacity: 0.12 + rng.nextDouble() * 0.10,
      delay: rng.nextDouble(),
    );
  });

  static final _particles = List<_Particle>.generate(8, (i) {
    final rng = Random(42 + i);
    return _Particle(
      nx: rng.nextDouble(),
      ny: rng.nextDouble(),
      size: 30 + rng.nextDouble() * 80,
      speed: 0.25 + rng.nextDouble() * 0.5,
      driftX: (rng.nextDouble() - 0.5) * 0.25,
      opacity: 0.03 + rng.nextDouble() * 0.05,
      delay: rng.nextDouble(),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final progress = _progress;

    _drawBaseGradient(canvas, size);

    final blobPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    for (final b in _blobs) {
      final t = (progress * b.speed + b.delay) % 1.0;
      final dx = sin(t * 2 * pi) * b.driftX * size.width;
      final dy = cos(t * 2 * pi) * b.driftY * size.height;
      final cx = b.nx * size.width + dx;
      final cy = b.ny * size.height + dy;

      final pulse = 0.8 + 0.2 * sin(t * pi * 2 * 0.7);
      final alpha = b.opacity * pulse;

      blobPaint.color = _cs.primary.withValues(alpha: alpha);
      canvas.drawCircle(Offset(cx, cy), b.radius, blobPaint);
    }

    final particlePaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    for (final p in _particles) {
      final t = (progress * p.speed + p.delay) % 1.0;
      final y = (p.ny - t) % 1.0;
      final x = (p.nx + sin(t * 2 * pi) * p.driftX) % 1.0;

      particlePaint.color = (_isDark ? Colors.white : _cs.primary)
          .withValues(alpha: p.opacity);

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x * size.width, y * size.height),
          width: p.size,
          height: p.size * 0.6,
        ),
        particlePaint,
      );
    }
  }

  void _drawBaseGradient(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _isDark ? Colors.black : Colors.white,
        _cs.surface,
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) {
    return oldDelegate._progress != _progress ||
        oldDelegate._isDark != _isDark;
  }
}

class _Blob {
  final double nx;
  final double ny;
  final double radius;
  final double speed;
  final double driftX;
  final double driftY;
  final double opacity;
  final double delay;

  const _Blob({
    required this.nx,
    required this.ny,
    required this.radius,
    required this.speed,
    required this.driftX,
    required this.driftY,
    required this.opacity,
    required this.delay,
  });
}

class _Particle {
  final double nx;
  final double ny;
  final double size;
  final double speed;
  final double driftX;
  final double opacity;
  final double delay;

  const _Particle({
    required this.nx,
    required this.ny,
    required this.size,
    required this.speed,
    required this.driftX,
    required this.opacity,
    required this.delay,
  });
}
