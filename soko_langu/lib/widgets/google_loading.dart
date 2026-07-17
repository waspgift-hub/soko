import 'dart:math';
import 'package:flutter/material.dart';

class GoogleLoading extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const GoogleLoading({
    super.key,
    this.size = 48,
    this.color,
    this.strokeWidth = 4,
  });

  @override
  State<GoogleLoading> createState() => _GoogleLoadingState();
}

class _GoogleLoadingState extends State<GoogleLoading>
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _Google2026Painter(
              rotation: _rotation.value,
              arcStart: _arcStart.value,
              arcSweep: _arcSweep.value,
              colors: const [Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853)],
              strokeWidth: widget.strokeWidth,
            ),
          ),
        );
      },
    );
  }
}

class _Google2026Painter extends CustomPainter {
  final double rotation;
  final double arcStart;
  final double arcSweep;
  final List<Color> colors;
  final double strokeWidth;

  _Google2026Painter({
    required this.rotation,
    required this.arcStart,
    required this.arcSweep,
    required this.colors,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final segmentSweep = arcSweep / colors.length;

    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final startAngle = rotation + arcStart * 2 * pi + i * segmentSweep * 2 * pi;
      final sweepAngle = segmentSweep * 2 * pi - 0.05;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Google2026Painter old) =>
      old.rotation != rotation ||
      old.arcStart != arcStart ||
      old.arcSweep != arcSweep;
}

class GoogleLoadingPage extends StatelessWidget {
  final double size;
  final Color? color;

  const GoogleLoadingPage({
    super.key,
    this.size = 48,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size + 32,
        height: size + 32,
        child: GoogleLoading(size: size, strokeWidth: 3),
      ),
    );
  }
}

class SkeletonLoader extends StatelessWidget {
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const _ShimmerEffect(),
    );
  }
}

class _ShimmerEffect extends StatefulWidget {
  const _ShimmerEffect();

  @override
  State<_ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<_ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(_animation.value, 0),
              end: Alignment(_animation.value + 0.5, 0),
              colors: [
                Theme.of(context).colorScheme.outline,
                Theme.of(context).colorScheme.surfaceContainerLow,
                Theme.of(context).colorScheme.outline,
              ],
            ).createShader(bounds);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}

