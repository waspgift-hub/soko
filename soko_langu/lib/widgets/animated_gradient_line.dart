import 'package:flutter/material.dart';

/// Subtle monochrome accent line that breathes opacity instead of sweeping a
/// gradient, so it reads as a quiet divider rather than a colorful streak.
class AnimatedGradientLine extends StatefulWidget {
  final double height;
  final Duration duration;
  final double borderRadius;

  const AnimatedGradientLine({
    super.key,
    this.height = 3,
    this.duration = const Duration(seconds: 3),
    this.borderRadius = 2,
  });

  @override
  State<AnimatedGradientLine> createState() => _AnimatedGradientLineState();
}

class _AnimatedGradientLineState extends State<AnimatedGradientLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.35 + t * 0.35),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}