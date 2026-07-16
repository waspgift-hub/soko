import 'package:flutter/material.dart';

class AnimatedGradientLine extends StatefulWidget {
  final double height;
  final List<Color> colors;
  final Duration duration;
  final double borderRadius;

  const AnimatedGradientLine({
    super.key,
    this.height = 3,
    this.colors = const [
      Color(0xFF6C63FF),
      Color(0xFFFF6584),
      Color(0xFFFFB84C),
      Color(0xFF00DBA5),
    ],
    this.duration = const Duration(seconds: 4),
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
      ..repeat();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
    ];

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(
          begin: Alignment(-1 + _controller.value * 2, 0),
          end: Alignment(1 - _controller.value * 2, 0),
          colors: themeColors,
        ),
      ),
    );
  }
}
