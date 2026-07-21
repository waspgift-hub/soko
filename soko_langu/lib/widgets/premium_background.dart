import 'dart:math';
import 'package:flutter/material.dart';

/// High-performance aurora background with mesh-gradient glow.
///
/// - Single [CustomPainter] renders everything (base gradient, aurora blobs,
///   floating particles) in one GPU pass.
/// - Wrapped in [RepaintBoundary] so background repaints never cause content
///   flicker when text inputs change or data loads.
/// - Animates on a 35 s loop; blobs drift slowly with sine-based motion.
class PremiumBackground extends StatelessWidget {
  final Widget child;
  const PremiumBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(
          child: _AuroraPanels(child: const _AuroraRender()),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Wraps [child] in an [AnimatedBuilder] driven by a shared controller so the
/// painter receives the current [progress] value.
///
/// It is separated from the [PremiumBackground] to guarantee the
/// [AnimationController] is disposed correctly (StatefulWidget).
class _AuroraPanels extends StatefulWidget {
  final Widget child;
  const _AuroraPanels({required this.child});

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
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        // Propagate progress to descendants via a trivial InheritedWidget.
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

/// The actual renderer — a [CustomPaint] whose [CustomPainter] draws the
/// base gradient, soft aurora blobs, and particles in one paint pass.
///
/// The widget itself is const; only the painter receives changing [progress].
class _AuroraRender extends StatelessWidget {
  const _AuroraRender();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _AuroraPainter(context: context),
        size: Size.infinite,
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Single painter — one canvas pass for ALL visual layers.
/// ---------------------------------------------------------------------------
class _AuroraPainter extends CustomPainter {
  final BuildContext context;

  _AuroraPainter({required this.context});

  // ---- Cached data (re‑built only when context changes) -------------------
  late final bool _isDark = Theme.of(context).brightness == Brightness.dark;
  late final ColorScheme _cs = Theme.of(context).colorScheme;
  late final double _progress = _AuroraProgress.of(context);

  // ---- Aurora blob definitions (deterministic, seeded) --------------------
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

  // ---- Particle definitions (deterministic, seeded) -----------------------
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

  // ---- Painters -----------------------------------------------------------
  @override
  void paint(Canvas canvas, Size size) {
    final progress = _progress;

    // 1. Base gradient
    _drawBaseGradient(canvas, size);

    // 2. Aurora blobs
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

    // 3. Floating particles (very soft blurred ovals)
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
    // Rebuild only when the InheritedWidget's progress changes.
    // Using context + InheritedWidget is cheaper than storing progress locally.
    return oldDelegate._progress != _progress ||
        oldDelegate._isDark != _isDark;
  }
}

// ---- Data classes (const) --------------------------------------------------

class _Blob {
  final double nx; // normalized x (0..1)
  final double ny; // normalized y (0..1)
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
