import 'dart:math';
import 'package:flutter/material.dart';

class SokoVibeLoading extends StatefulWidget {
  final double size;

  const SokoVibeLoading({super.key, this.size = 48});

  @override
  State<SokoVibeLoading> createState() => _SokoVibeLoadingState();
}

class _SokoVibeLoadingState extends State<SokoVibeLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotation;
  late Animation<double> _arcStart;
  late Animation<double> _arcSweep;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _rotation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );

    _arcStart = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.5).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.5, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_controller);

    _arcSweep = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.15, end: 0.75).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.75, end: 0.15).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.15, end: 0.15).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strokeWidth = widget.size * 0.12;
    final iconSize = widget.size * 0.4;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _SpinningArcsPainter(
                  rotation: _rotation.value,
                  arcStart: _arcStart.value,
                  arcSweep: _arcSweep.value,
                  strokeWidth: strokeWidth,
                  color: cs.primary,
                ),
              ),
              Icon(Icons.store_rounded, size: iconSize, color: cs.primary),
            ],
          ),
        );
      },
    );
  }
}

class _SpinningArcsPainter extends CustomPainter {
  final double rotation;
  final double arcStart;
  final double arcSweep;
  final double strokeWidth;
  final Color color;

  _SpinningArcsPainter({
    required this.rotation,
    required this.arcStart,
    required this.arcSweep,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2 - 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final startAngle = rotation + arcStart * 2 * pi;
    final sweepAngle = arcSweep * 2 * pi - 0.05;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinningArcsPainter old) =>
      old.rotation != rotation ||
      old.arcStart != arcStart ||
      old.arcSweep != arcSweep ||
      old.color != color;
}

class SokoVibeLoadingPage extends StatelessWidget {
  final double size;

  const SokoVibeLoadingPage({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Center(child: SokoVibeLoading(size: size));
  }
}

/// Branded Soko Vibe dot loader built from Google's four brand colors.
///
/// Four dots pulse in a staggered rhythm so the brand reads at a glance
/// wherever full-page loading states are shown.
class SokoVibeDotLoader extends StatefulWidget {
  final double size;

  const SokoVibeDotLoader({super.key, this.size = 48});

  @override
  State<SokoVibeDotLoader> createState() => _SokoVibeDotLoaderState();
}

class _SokoVibeDotLoaderState extends State<SokoVibeDotLoader>
    with SingleTickerProviderStateMixin {
  static const _googleColors = [
    Color(0xFF4285F4),
    Color(0xFFEA4335),
    Color(0xFFFBBC05),
    Color(0xFF34A853),
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotSize = widget.size * 0.4;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final phase = (_controller.value + i * 0.25) % 1.0;
              // Pulse scale: 0.4 -> 1.0 -> 0.4, offset per dot.
              final scale = 0.4 + 0.6 * (0.5 - 0.5 * cos(2 * pi * phase));
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 0.045),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: _googleColors[i],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _googleColors[i].withValues(alpha: 0.35),
                          blurRadius: dotSize * 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Full-page centered variant of [SokoVibeDotLoader].
class SokoVibeDotLoadingPage extends StatelessWidget {
  final double size;

  const SokoVibeDotLoadingPage({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Center(child: SokoVibeDotLoader(size: size));
  }
}

/// Minimal monochrome three-dot loader that matches the app's black/white
/// identity. Dots bounce in sequence — reads instantly and feels native
/// (Material/Apple style) rather than a spinner.
class SokoVibeThreeDotLoader extends StatefulWidget {
  final double size;
  final double dotSize;

  const SokoVibeThreeDotLoader({
    super.key,
    this.size = 40,
    this.dotSize = 10,
  });

  @override
  State<SokoVibeThreeDotLoader> createState() => _SokoVibeThreeDotLoaderState();
}

class _SokoVibeThreeDotLoaderState extends State<SokoVibeThreeDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final dimColor = color.withValues(alpha: 0.25);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final t = (_controller.value - i * 0.18) % 1.0;
              // Bounce: fast rise, gentle fall, resting pause.
              final scale = t < 0.3
                  ? (t / 0.3).clamp(0.0, 1.0)
                  : 1.0 - ((t - 0.3) / 0.7).clamp(0.0, 1.0) * 0.45;
              final isActive = t < 0.45;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.translate(
                  offset: Offset(0, -8 * (scale - 0.55)),
                  child: Opacity(
                    opacity: isActive ? 1.0 : 0.35,
                    child: Container(
                      width: widget.dotSize,
                      height: widget.dotSize,
                      decoration: BoxDecoration(
                        color: isActive ? color : dimColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Full-page centered [SokoVibeThreeDotLoader].
class SokoVibeThreeDotLoadingPage extends StatelessWidget {
  final double size;
  final double dotSize;

  const SokoVibeThreeDotLoadingPage({
    super.key,
    this.size = 40,
    this.dotSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Center(child: SokoVibeThreeDotLoader(size: size, dotSize: dotSize));
  }
}
