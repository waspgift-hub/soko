import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original animated empty-state illustrations, hand-drawn with
/// [CustomPainter] — no downloaded assets, no licenses, no attribution,
/// and zero bytes over the network (offline-first friendly).
///
/// Each looping widget repeats its controller; [SuccessCheckArt] plays
/// once. All painters are theme-aware through [color] and render at any
/// [size] via canvas scaling.

// ---------------------------------------------------------------------------
// Empty cart: bouncing basket + motion dots
// ---------------------------------------------------------------------------

class EmptyCartArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyCartArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyCartArt> createState() => _EmptyCartArtState();
}

class _EmptyCartArtState extends State<EmptyCartArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _CartPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _CartPainter extends CustomPainter {
  final double t;
  final Color color;

  _CartPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Gentle hop.
    final hop = -4 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(0, hop);
    // Handle.
    canvas.drawArc(
      const Rect.fromLTWH(30, 18, 36, 26),
      math.pi,
      math.pi,
      false,
      paint,
    );
    // Basket body.
    final body = Path()
      ..moveTo(28, 44)
      ..lineTo(68, 44)
      ..lineTo(61, 72)
      ..lineTo(35, 72)
      ..close();
    canvas.drawPath(body, paint);
    // Wheels.
    canvas.drawCircle(const Offset(39, 79), 3.5, paint);
    canvas.drawCircle(const Offset(57, 79), 3.5, paint);
    canvas.restore();

    // Motion dots fading behind the hop.
    for (var i = 0; i < 2; i++) {
      final phase = (t + i * 0.5) % 1.0;
      canvas.drawCircle(
        Offset(20 + i * 56, 30 + phase * 8),
        2.5,
        Paint()..color = color.withValues(alpha: 0.35 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_CartPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Empty wishlist: beating heart
// ---------------------------------------------------------------------------

class EmptyWishlistArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyWishlistArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyWishlistArt> createState() => _EmptyWishlistArtState();
}

class _EmptyWishlistArtState extends State<EmptyWishlistArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _HeartPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

Path _heartPath() {
  return Path()
    ..moveTo(48, 70)
    ..cubicTo(48, 70, 22, 52, 22, 36)
    ..cubicTo(22, 26, 30, 20, 38, 20)
    ..cubicTo(43, 20, 47, 24, 48, 28)
    ..cubicTo(49, 24, 53, 20, 58, 20)
    ..cubicTo(66, 20, 74, 26, 74, 36)
    ..cubicTo(74, 52, 48, 70, 48, 70)
    ..close();
}

class _HeartPainter extends CustomPainter {
  final double t;
  final Color color;

  _HeartPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    // Double-beat pulse (pow returns num — normalize to double).
    final beat =
        math.pow(math.max(0, math.sin(t * 2 * math.pi)), 3).toDouble();
    final echo =
        math.pow(math.max(0, math.sin((t - 0.18) * 2 * math.pi)), 6)
            .toDouble();
    final scale = 1 + 0.1 * beat + 0.06 * echo;
    canvas.save();
    canvas.translate(48, 45);
    canvas.scale(scale);
    canvas.translate(-48, -45);
    canvas.drawPath(
      _heartPath(),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Empty orders: floating-lid package
// ---------------------------------------------------------------------------

class EmptyOrdersArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyOrdersArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyOrdersArt> createState() => _EmptyOrdersArtState();
}

class _EmptyOrdersArtState extends State<EmptyOrdersArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _BoxPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final double t;
  final Color color;

  _BoxPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Body.
    canvas.drawRRect(
      RRect.fromLTRBR(28, 44, 68, 74, const Radius.circular(4)),
      paint,
    );
    // Tape seam.
    canvas.drawLine(const Offset(48, 44), const Offset(48, 74), paint);
    // Lid floats above the body.
    final lift = -3 * math.sin(t * 2 * math.pi);
    canvas.drawRRect(
      RRect.fromLTRBR(24, 32 + lift, 72, 42 + lift, const Radius.circular(3)),
      paint,
    );
    // Side flaps.
    canvas.drawLine(const Offset(28, 52), const Offset(20, 46), paint);
    canvas.drawLine(const Offset(68, 52), const Offset(76, 46), paint);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Empty chat: bubbles with typing dots
// ---------------------------------------------------------------------------

class EmptyChatArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyChatArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyChatArt> createState() => _EmptyChatArtState();
}

class _EmptyChatArtState extends State<EmptyChatArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _ChatPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _ChatPainter extends CustomPainter {
  final double t;
  final Color color;

  _ChatPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final faint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Main bubble.
    canvas.drawRRect(
      RRect.fromLTRBR(16, 24, 62, 52, const Radius.circular(10)),
      paint,
    );
    final tail = Path()
      ..moveTo(28, 52)
      ..lineTo(24, 62)
      ..lineTo(36, 52)
      ..close();
    canvas.drawPath(tail, paint);
    // Reply bubble.
    canvas.drawRRect(
      RRect.fromLTRBR(36, 56, 80, 76, const Radius.circular(8)),
      faint,
    );
    // Typing dots cycle inside the main bubble.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.22) % 1.0;
      final bounce = -3 * math.sin(phase * math.pi);
      canvas.drawCircle(
        Offset(30 + i * 9, 38 + bounce),
        2.8,
        Paint()..color = color.withValues(alpha: 0.45 + 0.55 * phase),
      );
    }
  }

  @override
  bool shouldRepaint(_ChatPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Empty search: sweeping magnifier
// ---------------------------------------------------------------------------

class EmptySearchArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptySearchArt({super.key, this.size = 96, this.color});

  @override
  State<EmptySearchArt> createState() => _EmptySearchArtState();
}

class _EmptySearchArtState extends State<EmptySearchArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _SearchPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _SearchPainter extends CustomPainter {
  final double t;
  final Color color;

  _SearchPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    // Lens + handle.
    canvas.drawCircle(const Offset(42, 42), 19, paint);
    canvas.drawLine(const Offset(55, 55), const Offset(71, 71), paint);
    // Radar sweep rotating around the lens.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(42, 42), radius: 19),
      t * 2 * math.pi - math.pi / 2,
      0.9,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    // Echo dot.
    final phase = (t * 2) % 1.0;
    canvas.drawCircle(
      const Offset(42, 42),
      3 + 3 * phase,
      Paint()..color = color.withValues(alpha: 0.4 * (1 - phase)),
    );
  }

  @override
  bool shouldRepaint(_SearchPainter old) => old.t != t || old.color != color;
}

// ---------------------------------------------------------------------------
// Success check: one-shot circle + tick draw
// ---------------------------------------------------------------------------

class SuccessCheckArt extends StatefulWidget {
  final double size;
  final Color? color;

  const SuccessCheckArt({super.key, this.size = 96, this.color});

  @override
  State<SuccessCheckArt> createState() => _SuccessCheckArtState();
}

class _SuccessCheckArtState extends State<SuccessCheckArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _CheckPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

Path _trimPath(Path source, double fraction) {
  final f = fraction.clamp(0.0, 1.0);
  if (f <= 0) return Path();
  final out = Path();
  for (final metric in source.computeMetrics()) {
    out.addPath(metric.extractPath(0, metric.length * f), Offset.zero);
  }
  return out;
}

class _CheckPainter extends CustomPainter {
  final double t;
  final Color color;

  _CheckPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Circle draws first, tick follows.
    final circleT = (t / 0.55).clamp(0.0, 1.0);
    final tickT = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: const Offset(48, 48), radius: 27));
    canvas.drawPath(_trimPath(circle, circleT), paint);
    final tick = Path()
      ..moveTo(36, 49)
      ..lineTo(46, 59)
      ..lineTo(62, 37);
    canvas.drawPath(_trimPath(tick, tickT), paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}
