import 'package:flutter/material.dart';

import 'soko_vibe_loading.dart';

/// Loading spinner (three dots) used across the app.
///
/// Delegates to [SokoVibeThreeDotLoader] so every loading state renders as
/// three dots. [color] overrides the theme seed color (e.g. white dots on a
/// colored button).
class GoogleLoading extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SokoVibeThreeDotLoader(
      size: size,
      dotSize: (size * 0.22).clamp(3.0, 12.0),
      color: color,
    );
  }
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
      child: SokoVibeThreeDotLoader(
        size: size * 0.82,
        dotSize: size * 0.22,
        color: color,
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
