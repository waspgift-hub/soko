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

  static const _colors = [
    Color(0xFF4285F4),
    Color(0xFFEA4335),
    Color(0xFFFBBC05),
    Color(0xFF34A853),
  ];

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
                ),
              ),
              Icon(Icons.shopping_cart, size: iconSize, color: Theme.of(context).colorScheme.primary),
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

  _SpinningArcsPainter({
    required this.rotation,
    required this.arcStart,
    required this.arcSweep,
    required this.strokeWidth,
  });

  static const _colors = [
    Color(0xFF4285F4),
    Color(0xFFEA4335),
    Color(0xFFFBBC05),
    Color(0xFF34A853),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2 - 2;
    final segmentSweep = arcSweep / _colors.length;

    for (int i = 0; i < _colors.length; i++) {
      final paint = Paint()
        ..color = _colors[i]
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
  bool shouldRepaint(_SpinningArcsPainter old) =>
      old.rotation != rotation || old.arcStart != arcStart || old.arcSweep != arcSweep;
}

class SokoVibeLoadingPage extends StatelessWidget {
  final double size;

  const SokoVibeLoadingPage({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Center(child: SokoVibeLoading(size: size));
  }
}
