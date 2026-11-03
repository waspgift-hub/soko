import 'package:flutter/material.dart';

/// Three-dot loading indicator (lazy-load placeholder spec): three dots
/// pulse in sequence. Purely decorative — build it into image placeholders.
class DsLoadingDots extends StatefulWidget {
  final double size;
  final Color? color;

  const DsLoadingDots({super.key, this.size = 8, this.color});

  @override
  State<DsLoadingDots> createState() => _DsLoadingDotsState();
}

class _DsLoadingDotsState extends State<DsLoadingDots>
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
    final dotColor =
        widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot peaks at 1.0 when its turn comes every 1/3 of a cycle
            final phase = ((t - i / 3) % 1.0 + 1.0) % 1.0;
            final scale = 0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Container(
              width: widget.size,
              height: widget.size,
              margin: EdgeInsets.symmetric(horizontal: widget.size * 0.35),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor.withValues(alpha: 0.35 + 0.65 * scale),
              ),
              transform: Matrix4.identity()..scale(scale),
            );
          }),
        );
      },
    );
  }
}