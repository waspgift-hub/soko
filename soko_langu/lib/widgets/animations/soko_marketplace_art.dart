import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Additional hand-drawn animated illustrations for marketplace states.
///
/// These follow the same conventions as [soko_animated_art.dart]: no bundled
/// assets, theme-aware through [color], canvas scaling from a 96x96 design
/// grid, and looping controllers that are paused by [TickerMode].

class NoInternetArt extends StatefulWidget {
  final double size;
  final Color? color;

  const NoInternetArt({super.key, this.size = 96, this.color});

  @override
  State<NoInternetArt> createState() => _NoInternetArtState();
}

class _NoInternetArtState extends State<NoInternetArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
      ..repeat();
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
          painter: _NoInternetPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _NoInternetPainter extends CustomPainter {
  final double t;
  final Color color;

  _NoInternetPainter({required this.t, required this.color});

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

    // Cloud.
    canvas.drawArc(const Rect.fromLTWH(24, 28, 24, 24), math.pi, math.pi, false, paint);
    canvas.drawArc(const Rect.fromLTWH(40, 22, 30, 30), math.pi, math.pi, false, paint);
    canvas.drawArc(const Rect.fromLTWH(62, 30, 18, 18), math.pi, math.pi, false, paint);
    canvas.drawLine(const Offset(24, 40), const Offset(80, 40), paint);

    // Broken wifi arcs.
    canvas.drawArc(const Rect.fromLTWH(34, 52, 28, 28), math.pi * 1.15, 0.9, false, paint);
    canvas.drawArc(const Rect.fromLTWH(40, 58, 16, 16), math.pi * 1.15, 0.9, false, paint);
    canvas.drawCircle(const Offset(48, 78), 3, Paint()..color = color);

    // Slash.
    canvas.drawLine(
      const Offset(26, 74),
      const Offset(70, 46),
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    // Falling rain dots.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.33) % 1.0;
      canvas.drawCircle(
        Offset(32 + i * 16, 44 + phase * 18),
        2.4,
        Paint()..color = color.withValues(alpha: 0.45 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_NoInternetPainter old) => old.t != t || old.color != color;
}

class UploadArt extends StatefulWidget {
  final double size;
  final Color? color;

  const UploadArt({super.key, this.size = 96, this.color});

  @override
  State<UploadArt> createState() => _UploadArtState();
}

class _UploadArtState extends State<UploadArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          painter: _UploadPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _UploadPainter extends CustomPainter {
  final double t;
  final Color color;

  _UploadPainter({required this.t, required this.color});

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

    // Tray.
    canvas.drawRRect(RRect.fromLTRBR(24, 62, 72, 78, const Radius.circular(6)), paint);
    canvas.drawLine(const Offset(24, 62), const Offset(34, 52), paint);
    canvas.drawLine(const Offset(72, 62), const Offset(62, 52), paint);

    // Rising arrow.
    final lift = -10 * (0.5 - (t - 0.5).abs());
    canvas.drawLine(Offset(48, 50 + lift), Offset(48, 24 + lift), paint);
    canvas.drawLine(Offset(48, 24 + lift), Offset(38, 34 + lift), paint);
    canvas.drawLine(Offset(48, 24 + lift), Offset(58, 34 + lift), paint);

    // Progress dots.
    for (var i = 0; i < 3; i++) {
      final phase = (t * 2 + i * 0.25) % 1.0;
      canvas.drawCircle(
        Offset(40 + i * 8, 70),
        2.5,
        Paint()..color = color.withValues(alpha: 0.35 + 0.65 * phase),
      );
    }
  }

  @override
  bool shouldRepaint(_UploadPainter old) => old.t != t || old.color != color;
}

class DownloadArt extends StatefulWidget {
  final double size;
  final Color? color;

  const DownloadArt({super.key, this.size = 96, this.color});

  @override
  State<DownloadArt> createState() => _DownloadArtState();
}

class _DownloadArtState extends State<DownloadArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          painter: _DownloadPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _DownloadPainter extends CustomPainter {
  final double t;
  final Color color;

  _DownloadPainter({required this.t, required this.color});

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

    // Cloud.
    canvas.drawArc(const Rect.fromLTWH(24, 20, 24, 24), math.pi, math.pi, false, paint);
    canvas.drawArc(const Rect.fromLTWH(40, 14, 30, 30), math.pi, math.pi, false, paint);
    canvas.drawArc(const Rect.fromLTWH(62, 22, 18, 18), math.pi, math.pi, false, paint);
    canvas.drawLine(const Offset(24, 32), const Offset(80, 32), paint);

    // Descending arrow.
    final drop = 10 * (0.5 - (t - 0.5).abs());
    canvas.drawLine(Offset(48, 40), Offset(48, 64 + drop), paint);
    canvas.drawLine(Offset(48, 64 + drop), Offset(38, 54 + drop), paint);
    canvas.drawLine(Offset(48, 64 + drop), Offset(58, 54 + drop), paint);

    // Tray.
    canvas.drawRRect(RRect.fromLTRBR(30, 74, 66, 84, const Radius.circular(5)), paint);
  }

  @override
  bool shouldRepaint(_DownloadPainter old) => old.t != t || old.color != color;
}

class PaymentPendingArt extends StatefulWidget {
  final double size;
  final Color? color;

  const PaymentPendingArt({super.key, this.size = 96, this.color});

  @override
  State<PaymentPendingArt> createState() => _PaymentPendingArtState();
}

class _PaymentPendingArtState extends State<PaymentPendingArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
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
          painter: _PaymentPendingPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _PaymentPendingPainter extends CustomPainter {
  final double t;
  final Color color;

  _PaymentPendingPainter({required this.t, required this.color});

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

    // Coin.
    canvas.drawCircle(const Offset(48, 48), 24, paint);
    canvas.drawLine(const Offset(48, 34), const Offset(48, 48), paint);
    canvas.drawLine(const Offset(48, 48), const Offset(58, 54), paint);

    // Clock ticks.
    final angle = t * 2 * math.pi;
    canvas.drawCircle(
      Offset(48 + 20 * math.cos(angle), 48 + 20 * math.sin(angle)),
      3,
      Paint()..color = color.withValues(alpha: 0.7),
    );

    // Sand dots.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.3) % 1.0;
      canvas.drawCircle(
        Offset(48, 78 - phase * 14),
        2.5,
        Paint()..color = color.withValues(alpha: 0.5 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_PaymentPendingPainter old) => old.t != t || old.color != color;
}

class PaymentProcessingArt extends StatefulWidget {
  final double size;
  final Color? color;

  const PaymentProcessingArt({super.key, this.size = 96, this.color});

  @override
  State<PaymentProcessingArt> createState() => _PaymentProcessingArtState();
}

class _PaymentProcessingArtState extends State<PaymentProcessingArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
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
          painter: _PaymentProcessingPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _PaymentProcessingPainter extends CustomPainter {
  final double t;
  final Color color;

  _PaymentProcessingPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(const Offset(48, 48), 24, paint);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(48, 48), radius: 30),
      t * 2 * math.pi,
      math.pi * 1.2,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(const Offset(40, 48), const Offset(56, 48), paint);
    canvas.drawLine(const Offset(48, 40), const Offset(48, 56), paint);
  }

  @override
  bool shouldRepaint(_PaymentProcessingPainter old) => old.t != t || old.color != color;
}

class OrderConfirmedArt extends StatefulWidget {
  final double size;
  final Color? color;

  const OrderConfirmedArt({super.key, this.size = 96, this.color});

  @override
  State<OrderConfirmedArt> createState() => _OrderConfirmedArtState();
}

class _OrderConfirmedArtState extends State<OrderConfirmedArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
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
          painter: _OrderConfirmedPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _OrderConfirmedPainter extends CustomPainter {
  final double t;
  final Color color;

  _OrderConfirmedPainter({required this.t, required this.color});

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

    final circleT = (t / 0.5).clamp(0.0, 1.0);
    final tickT = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(48, 48), radius: 28),
      -math.pi / 2,
      2 * math.pi * circleT,
      false,
      paint,
    );
    final tick = Path()
      ..moveTo(34, 50)
      ..lineTo(44, 60)
      ..lineTo(62, 38);
    canvas.drawPath(_trimPath(tick, tickT), paint);

    // Box outline.
    canvas.drawRRect(RRect.fromLTRBR(30, 68, 66, 84, const Radius.circular(4)), paint);
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

  @override
  bool shouldRepaint(_OrderConfirmedPainter old) => old.t != t || old.color != color;
}

class SellerDashboardArt extends StatefulWidget {
  final double size;
  final Color? color;

  const SellerDashboardArt({super.key, this.size = 96, this.color});

  @override
  State<SellerDashboardArt> createState() => _SellerDashboardArtState();
}

class _SellerDashboardArtState extends State<SellerDashboardArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
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
          painter: _SellerDashboardPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _SellerDashboardPainter extends CustomPainter {
  final double t;
  final Color color;

  _SellerDashboardPainter({required this.t, required this.color});

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

    // Chart frame.
    canvas.drawLine(const Offset(20, 76), const Offset(76, 76), paint);
    canvas.drawLine(const Offset(20, 24), const Offset(20, 76), paint);

    final heights = [20.0, 34.0, 26.0, 46.0, 38.0];
    for (var i = 0; i < heights.length; i++) {
      final pulse = 0.85 + 0.15 * math.sin((t + i * 0.18) * 2 * math.pi);
      final h = heights[i] * pulse;
      canvas.drawRRect(
        RRect.fromLTRBR(26 + i * 10, 76 - h, 32 + i * 10, 76, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.25 + 0.5 * (i / heights.length)),
      );
      canvas.drawRRect(
        RRect.fromLTRBR(26 + i * 10, 76 - h, 32 + i * 10, 76, const Radius.circular(3)),
        paint,
      );
    }

    // Coin.
    canvas.drawCircle(const Offset(72, 34), 12, paint);
    canvas.drawLine(const Offset(72, 28), const Offset(72, 40), paint);
    canvas.drawLine(const Offset(66, 34), const Offset(78, 34), paint);
  }

  @override
  bool shouldRepaint(_SellerDashboardPainter old) => old.t != t || old.color != color;
}

class ProductCreatedArt extends StatefulWidget {
  final double size;
  final Color? color;

  const ProductCreatedArt({super.key, this.size = 96, this.color});

  @override
  State<ProductCreatedArt> createState() => _ProductCreatedArtState();
}

class _ProductCreatedArtState extends State<ProductCreatedArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
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
          painter: _ProductCreatedPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _ProductCreatedPainter extends CustomPainter {
  final double t;
  final Color color;

  _ProductCreatedPainter({required this.t, required this.color});

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

    // Box.
    canvas.drawRRect(RRect.fromLTRBR(30, 42, 66, 74, const Radius.circular(5)), paint);
    canvas.drawLine(const Offset(48, 42), const Offset(48, 74), paint);
    canvas.drawRRect(RRect.fromLTRBR(26, 34, 70, 44, const Radius.circular(4)), paint);

    // Sparkles.
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 + t * 2 * math.pi;
      final radius = 16 + 6 * math.sin(t * 2 * math.pi + i);
      final center = Offset(48 + radius * math.cos(angle), 24 + radius * math.sin(angle) * 0.5);
      canvas.drawLine(
        center - const Offset(4, 0),
        center + const Offset(4, 0),
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        center - const Offset(0, 4),
        center + const Offset(0, 4),
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ProductCreatedPainter old) => old.t != t || old.color != color;
}

class KycPendingArt extends StatefulWidget {
  final double size;
  final Color? color;

  const KycPendingArt({super.key, this.size = 96, this.color});

  @override
  State<KycPendingArt> createState() => _KycPendingArtState();
}

class _KycPendingArtState extends State<KycPendingArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
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
          painter: _KycPendingPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _KycPendingPainter extends CustomPainter {
  final double t;
  final Color color;

  _KycPendingPainter({required this.t, required this.color});

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

    // Shield.
    final shield = Path()
      ..moveTo(48, 18)
      ..lineTo(72, 28)
      ..lineTo(72, 52)
      ..quadraticBezierTo(72, 72, 48, 82)
      ..quadraticBezierTo(24, 72, 24, 52)
      ..lineTo(24, 28)
      ..close();
    canvas.drawPath(shield, paint);

    // Clock.
    canvas.drawCircle(const Offset(48, 50), 14, paint);
    canvas.drawLine(const Offset(48, 42), const Offset(48, 50), paint);
    final angle = t * 2 * math.pi;
    canvas.drawLine(
      const Offset(48, 50),
      Offset(48 + 9 * math.cos(angle), 50 + 9 * math.sin(angle)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_KycPendingPainter old) => old.t != t || old.color != color;
}

class KycVerifiedArt extends StatefulWidget {
  final double size;
  final Color? color;

  const KycVerifiedArt({super.key, this.size = 96, this.color});

  @override
  State<KycVerifiedArt> createState() => _KycVerifiedArtState();
}

class _KycVerifiedArtState extends State<KycVerifiedArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
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
          painter: _KycVerifiedPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _KycVerifiedPainter extends CustomPainter {
  final double t;
  final Color color;

  _KycVerifiedPainter({required this.t, required this.color});

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

    final shield = Path()
      ..moveTo(48, 18)
      ..lineTo(72, 28)
      ..lineTo(72, 52)
      ..quadraticBezierTo(72, 72, 48, 82)
      ..quadraticBezierTo(24, 72, 24, 52)
      ..lineTo(24, 28)
      ..close();
    canvas.drawPath(shield, paint);

    final tickT = t.clamp(0.0, 1.0);
    final tick = Path()
      ..moveTo(36, 50)
      ..lineTo(45, 59)
      ..lineTo(62, 40);
    canvas.drawPath(_trimPath(tick, tickT), paint);
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

  @override
  bool shouldRepaint(_KycVerifiedPainter old) => old.t != t || old.color != color;
}

class NotificationArt extends StatefulWidget {
  final double size;
  final Color? color;

  const NotificationArt({super.key, this.size = 96, this.color});

  @override
  State<NotificationArt> createState() => _NotificationArtState();
}

class _NotificationArtState extends State<NotificationArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
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
          painter: _NotificationPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _NotificationPainter extends CustomPainter {
  final double t;
  final Color color;

  _NotificationPainter({required this.t, required this.color});

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

    final swing = 6 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(48, 30);
    canvas.rotate(swing * math.pi / 180);
    canvas.translate(-48, -30);

    canvas.drawArc(const Rect.fromLTWH(30, 24, 36, 40), math.pi, math.pi, false, paint);
    canvas.drawLine(const Offset(30, 44), const Offset(30, 56), paint);
    canvas.drawLine(const Offset(66, 44), const Offset(66, 56), paint);
    canvas.drawArc(const Rect.fromLTWH(42, 56, 12, 10), 0, math.pi, false, paint);
    canvas.restore();

    // Clapper.
    canvas.drawCircle(const Offset(48, 68), 4, paint);

    // Dot pulse.
    final pulse = 0.7 + 0.3 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(
      const Offset(70, 24),
      6 * pulse,
      Paint()..color = color.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_NotificationPainter old) => old.t != t || old.color != color;
}

class RecentlyViewedArt extends StatefulWidget {
  final double size;
  final Color? color;

  const RecentlyViewedArt({super.key, this.size = 96, this.color});

  @override
  State<RecentlyViewedArt> createState() => _RecentlyViewedArtState();
}

class _RecentlyViewedArtState extends State<RecentlyViewedArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
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
          painter: _RecentlyViewedPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _RecentlyViewedPainter extends CustomPainter {
  final double t;
  final Color color;

  _RecentlyViewedPainter({required this.t, required this.color});

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

    // Eye.
    canvas.drawOval(const Rect.fromLTWH(20, 34, 56, 30), paint);
    canvas.drawCircle(const Offset(48, 49), 10, paint);

    // Clock hand sweeps.
    final angle = t * 2 * math.pi;
    canvas.drawCircle(const Offset(74, 72), 12, paint);
    canvas.drawLine(const Offset(74, 72), Offset(74, 64), paint);
    canvas.drawLine(
      const Offset(74, 72),
      Offset(74 + 8 * math.cos(angle), 72 + 8 * math.sin(angle)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RecentlyViewedPainter old) => old.t != t || old.color != color;
}

class EmptyCategoryArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyCategoryArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyCategoryArt> createState() => _EmptyCategoryArtState();
}

class _EmptyCategoryArtState extends State<EmptyCategoryArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
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
          painter: _EmptyCategoryPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyCategoryPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyCategoryPainter({required this.t, required this.color});

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

    // Folder.
    canvas.drawRRect(RRect.fromLTRBR(22, 34, 74, 74, const Radius.circular(6)), paint);
    canvas.drawRRect(RRect.fromLTRBR(22, 26, 46, 38, const Radius.circular(5)), paint);

    // Floating tag.
    final lift = -4 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(0, lift);
    canvas.drawRRect(RRect.fromLTRBR(48, 46, 70, 62, const Radius.circular(4)), paint);
    canvas.drawCircle(const Offset(54, 54), 2.5, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmptyCategoryPainter old) => old.t != t || old.color != color;
}

class EmptyProductsArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyProductsArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyProductsArt> createState() => _EmptyProductsArtState();
}

class _EmptyProductsArtState extends State<EmptyProductsArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
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
          painter: _EmptyProductsPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyProductsPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyProductsPainter({required this.t, required this.color});

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

    final hop = -3 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(0, hop);
    canvas.drawRRect(RRect.fromLTRBR(28, 44, 68, 74, const Radius.circular(5)), paint);
    canvas.drawLine(const Offset(28, 56), const Offset(68, 56), paint);
    canvas.drawRRect(RRect.fromLTRBR(24, 34, 72, 44, const Radius.circular(4)), paint);
    canvas.restore();

    // Sparkle.
    final twinkle = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(
      const Offset(76, 28),
      4 * twinkle,
      Paint()..color = color.withValues(alpha: 0.7 * twinkle),
    );
  }

  @override
  bool shouldRepaint(_EmptyProductsPainter old) => old.t != t || old.color != color;
}

class EmptyMusicArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyMusicArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyMusicArt> createState() => _EmptyMusicArtState();
}

class _EmptyMusicArtState extends State<EmptyMusicArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          painter: _EmptyMusicPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyMusicPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyMusicPainter({required this.t, required this.color});

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

    // Note.
    canvas.drawCircle(const Offset(34, 68), 8, paint);
    canvas.drawLine(const Offset(42, 68), const Offset(42, 30), paint);
    canvas.drawLine(const Offset(42, 30), const Offset(66, 24), paint);
    canvas.drawLine(const Offset(66, 24), const Offset(66, 58), paint);
    canvas.drawCircle(const Offset(58, 58), 8, paint);

    // Sound waves.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.2) % 1.0;
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(74, 42), radius: 8 + i * 6),
        -0.7,
        1.4,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.5 * (1 - phase))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_EmptyMusicPainter old) => old.t != t || old.color != color;
}

class EmptyLocationArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyLocationArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyLocationArt> createState() => _EmptyLocationArtState();
}

class _EmptyLocationArtState extends State<EmptyLocationArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          painter: _EmptyLocationPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyLocationPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyLocationPainter({required this.t, required this.color});

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

    final bounce = -5 * math.sin(t * 2 * math.pi).abs();
    canvas.save();
    canvas.translate(0, bounce);
    canvas.drawCircle(const Offset(48, 30), 12, paint);
    canvas.drawLine(const Offset(48, 42), const Offset(48, 62), paint);
    canvas.drawCircle(const Offset(48, 66), 4, paint);
    canvas.restore();

    // Radar rings.
    for (var i = 0; i < 2; i++) {
      final phase = (t + i * 0.5) % 1.0;
      canvas.drawCircle(
        const Offset(48, 66),
        10 + 16 * phase,
        Paint()
          ..color = color.withValues(alpha: 0.35 * (1 - phase))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_EmptyLocationPainter old) => old.t != t || old.color != color;
}

class EmptyNotificationsArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyNotificationsArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyNotificationsArt> createState() => _EmptyNotificationsArtState();
}

class _EmptyNotificationsArtState extends State<EmptyNotificationsArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          painter: _EmptyNotificationsPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyNotificationsPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyNotificationsPainter({required this.t, required this.color});

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

    final swing = 5 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(48, 28);
    canvas.rotate(swing * math.pi / 180);
    canvas.translate(-48, -28);
    canvas.drawArc(const Rect.fromLTWH(32, 24, 32, 36), math.pi, math.pi, false, paint);
    canvas.drawLine(const Offset(32, 42), const Offset(32, 56), paint);
    canvas.drawLine(const Offset(64, 42), const Offset(64, 56), paint);
    canvas.drawArc(const Rect.fromLTWH(42, 56, 12, 10), 0, math.pi, false, paint);
    canvas.restore();
    canvas.drawCircle(const Offset(48, 68), 3, paint);

    // Zzz.
    final phase = (t * 1.5) % 1.0;
    for (var i = 0; i < 2; i++) {
      canvas.drawText(
        'z',
        Offset(68 + i * 8, 24 - phase * 10 + i * 6),
        Paint()..color = color.withValues(alpha: 0.5 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_EmptyNotificationsPainter old) => old.t != t || old.color != color;
}

class EmptyTransactionsArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyTransactionsArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyTransactionsArt> createState() => _EmptyTransactionsArtState();
}

class _EmptyTransactionsArtState extends State<EmptyTransactionsArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
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
          painter: _EmptyTransactionsPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyTransactionsPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyTransactionsPainter({required this.t, required this.color});

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

    // Receipt.
    canvas.drawRRect(RRect.fromLTRBR(30, 20, 66, 78, const Radius.circular(4)), paint);
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(38, 34 + i * 10),
        Offset(58, 34 + i * 10),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Coin.
    final pulse = 0.85 + 0.15 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(const Offset(76, 64), 10 * pulse, paint);
    canvas.drawLine(const Offset(76, 60), const Offset(76, 68), paint);
    canvas.drawLine(const Offset(72, 64), const Offset(80, 64), paint);
  }

  @override
  bool shouldRepaint(_EmptyTransactionsPainter old) => old.t != t || old.color != color;
}

class EmptyShippingArt extends StatefulWidget {
  final double size;
  final Color? color;

  const EmptyShippingArt({super.key, this.size = 96, this.color});

  @override
  State<EmptyShippingArt> createState() => _EmptyShippingArtState();
}

class _EmptyShippingArtState extends State<EmptyShippingArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
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
          painter: _EmptyShippingPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _EmptyShippingPainter extends CustomPainter {
  final double t;
  final Color color;

  _EmptyShippingPainter({required this.t, required this.color});

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

    final move = 8 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(move, 0);

    // Truck body.
    canvas.drawRRect(RRect.fromLTRBR(24, 42, 62, 70, const Radius.circular(5)), paint);
    canvas.drawRRect(RRect.fromLTRBR(62, 48, 76, 70, const Radius.circular(4)), paint);
    canvas.drawCircle(const Offset(34, 76), 5, paint);
    canvas.drawCircle(const Offset(68, 76), 5, paint);
    canvas.restore();

    // Road dashes.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.33) % 1.0;
      canvas.drawLine(
        Offset(16 + i * 28 + phase * 12, 82),
        Offset(28 + i * 28 + phase * 12, 82),
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_EmptyShippingPainter old) => old.t != t || old.color != color;
}

class ErrorRetryArt extends StatefulWidget {
  final double size;
  final Color? color;

  const ErrorRetryArt({super.key, this.size = 96, this.color});

  @override
  State<ErrorRetryArt> createState() => _ErrorRetryArtState();
}

class _ErrorRetryArtState extends State<ErrorRetryArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.error;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _ErrorRetryPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _ErrorRetryPainter extends CustomPainter {
  final double t;
  final Color color;

  _ErrorRetryPainter({required this.t, required this.color});

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

    // Warning triangle.
    canvas.drawPath(
      Path()
        ..moveTo(48, 24)
        ..lineTo(78, 74)
        ..lineTo(18, 74)
        ..close(),
      paint,
    );
    canvas.drawLine(const Offset(48, 40), const Offset(48, 56), paint);
    canvas.drawCircle(const Offset(48, 64), 3, Paint()..color = color);

    // Retry arrow.
    final angle = t * 2 * math.pi;
    canvas.save();
    canvas.translate(74, 24);
    canvas.rotate(angle);
    canvas.drawArc(const Rect.fromLTWH(-10, -10, 20, 20), 0.2, 5.0, false, paint);
    canvas.drawLine(const Offset(10, 0), const Offset(4, -6), paint);
    canvas.drawLine(const Offset(10, 0), const Offset(4, 6), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ErrorRetryPainter old) => old.t != t || old.color != color;
}

class SplashArt extends StatefulWidget {
  final double size;
  final Color? color;

  const SplashArt({super.key, this.size = 96, this.color});

  @override
  State<SplashArt> createState() => _SplashArtState();
}

class _SplashArtState extends State<SplashArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
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
          painter: _SplashPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  final double t;
  final Color color;

  _SplashPainter({required this.t, required this.color});

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

    // Market bag.
    final hop = -4 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(0, hop);
    canvas.drawRRect(RRect.fromLTRBR(30, 34, 66, 74, const Radius.circular(6)), paint);
    canvas.drawArc(const Rect.fromLTWH(36, 20, 24, 24), math.pi, math.pi, false, paint);
    canvas.restore();

    // Sparkles.
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2 + t * 2 * math.pi;
      final center = Offset(48 + 22 * math.cos(angle), 48 + 22 * math.sin(angle));
      canvas.drawCircle(center, 2.5, Paint()..color = color.withValues(alpha: 0.65));
    }
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.t != t || old.color != color;
}

class OnboardingArt extends StatefulWidget {
  final double size;
  final Color? color;

  const OnboardingArt({super.key, this.size = 96, this.color});

  @override
  State<OnboardingArt> createState() => _OnboardingArtState();
}

class _OnboardingArtState extends State<OnboardingArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
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
          painter: _OnboardingPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _OnboardingPainter extends CustomPainter {
  final double t;
  final Color color;

  _OnboardingPainter({required this.t, required this.color});

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

    // Two people.
    canvas.drawCircle(const Offset(34, 34), 8, paint);
    canvas.drawArc(const Rect.fromLTWH(24, 44, 20, 24), math.pi, math.pi, false, paint);
    canvas.drawCircle(const Offset(62, 34), 8, paint);
    canvas.drawArc(const Rect.fromLTWH(52, 44, 20, 24), math.pi, math.pi, false, paint);

    // Handshake in the middle.
    final pulse = 0.9 + 0.1 * math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(48, 58);
    canvas.scale(pulse);
    canvas.translate(-48, -58);
    canvas.drawLine(const Offset(40, 58), const Offset(56, 58), paint);
    canvas.drawLine(const Offset(40, 58), const Offset(34, 52), paint);
    canvas.drawLine(const Offset(56, 58), const Offset(62, 52), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OnboardingPainter old) => old.t != t || old.color != color;
}

class HomePromoArt extends StatefulWidget {
  final double size;
  final Color? color;

  const HomePromoArt({super.key, this.size = 96, this.color});

  @override
  State<HomePromoArt> createState() => _HomePromoArtState();
}

class _HomePromoArtState extends State<HomePromoArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          painter: _HomePromoPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _HomePromoPainter extends CustomPainter {
  final double t;
  final Color color;

  _HomePromoPainter({required this.t, required this.color});

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

    // Megaphone.
    canvas.drawPath(
      Path()
        ..moveTo(26, 40)
        ..lineTo(46, 34)
        ..lineTo(46, 62)
        ..lineTo(26, 56)
        ..close(),
      paint,
    );
    canvas.drawLine(const Offset(46, 34), const Offset(66, 26), paint);
    canvas.drawLine(const Offset(46, 62), const Offset(66, 70), paint);
    canvas.drawLine(const Offset(66, 26), const Offset(66, 70), paint);

    // Sound waves.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.25) % 1.0;
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(66, 48), radius: 12 + i * 8),
        -0.6,
        1.2,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.5 * (1 - phase))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HomePromoPainter old) => old.t != t || old.color != color;
}

class ProductLoadingArt extends StatefulWidget {
  final double size;
  final Color? color;

  const ProductLoadingArt({super.key, this.size = 96, this.color});

  @override
  State<ProductLoadingArt> createState() => _ProductLoadingArtState();
}

class _ProductLoadingArtState extends State<ProductLoadingArt> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
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
          painter: _ProductLoadingPainter(t: _ctrl.value, color: color),
        ),
      ),
    );
  }
}

class _ProductLoadingPainter extends CustomPainter {
  final double t;
  final Color color;

  _ProductLoadingPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96;
    canvas.scale(s);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    // Card skeleton.
    canvas.drawRRect(RRect.fromLTRBR(22, 20, 74, 80, const Radius.circular(8)), paint);

    // Shimmer band.
    final band = (t * 1.4) % 1.0;
    final rect = Rect.fromLTWH(22 + 52 * band - 26, 20, 26, 60);
    canvas.save();
    canvas.clipRRect(RRect.fromLTRBR(22, 20, 74, 80, const Radius.circular(8)));
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.18));
    canvas.restore();

    // Lines.
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(30, 34 + i * 14, 66, 40 + i * 14, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_ProductLoadingPainter old) => old.t != t || old.color != color;
}

// Canvas.drawText extension helper.
extension _CanvasText on Canvas {
  void drawText(String text, Offset offset, Paint paint) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: paint.color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(this, offset);
  }
}

extension _Canvas on Canvas {
  // no-op placeholder
}
