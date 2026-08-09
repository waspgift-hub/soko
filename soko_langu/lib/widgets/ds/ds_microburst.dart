import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';

/// Rive-style "sent" micro-burst: an expanding ring plus a few dots that
/// radiates from a control (send button, reply button) each time [trigger]
/// increments — a cheap reaction with no third-party package.
class DsMicroBurst extends StatefulWidget {
  final Color color;
  final int trigger;
  final double size;

  const DsMicroBurst({
    super.key,
    required this.color,
    required this.trigger,
    this.size = 56,
  });

  @override
  State<DsMicroBurst> createState() => _DsMicroBurstState();
}

class _DsMicroBurstState extends State<DsMicroBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.celebration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant DsMicroBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          if (t <= 0 || t >= 1) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _MicroBurstPainter(
              color: widget.color,
              progress: t,
            ),
          );
        },
      ),
    );
  }
}

class _MicroBurstPainter extends CustomPainter {
  final Color color;
  final double progress;

  _MicroBurstPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final t = progress;

    // Expanding hairline ring.
    final ringT = Curves.easeOutCubic.transform(t);
    final ringRadius = ringT * size.width * 0.42;
    final ringOpacity = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: ringOpacity * 0.9),
    );

    // A few dots on the ring, evenly spaced.
    final dotCount = 6;
    for (var i = 0; i < dotCount; i++) {
      final angle = i * 2 * pi / dotCount;
      final dotPos = center + Offset(cos(angle), sin(angle)) * ringRadius;
      canvas.drawCircle(
        dotPos,
        (2.5 - t * 1.5).clamp(0.5, 2.5),
        Paint()..color = color.withValues(alpha: ringOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(_MicroBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
