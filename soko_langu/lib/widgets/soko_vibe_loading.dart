import 'package:flutter/material.dart';

/// Three-dot bounce loader — the app's single loading indicator.
///
/// Dots animate in sequence and inherit the theme seed color (via
/// `colorScheme.primary`) unless an explicit [color] is given. All other
/// loader widgets in the app delegate to this one so every loading state
/// renders as three dots.
class SokoVibeThreeDotLoader extends StatefulWidget {
  final double size;
  final double dotSize;
  final Color? color;

  const SokoVibeThreeDotLoader({
    super.key,
    this.size = 40,
    this.dotSize = 10,
    this.color,
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
    final base = widget.color ?? Theme.of(context).colorScheme.primary;
    final dot = widget.dotSize;
    // Auto-fit spacing so the loader never overflows at any size.
    final pad = ((widget.size - 3 * dot) / 6).clamp(0.5, 8.0).toDouble();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final t = (_controller.value - i * 0.18) % 1.0;
              // Bounce: fast rise, gentle fall, resting pause.
              final scale = t < 0.3
                  ? (t / 0.3).clamp(0.0, 1.0)
                  : 1.0 - ((t - 0.3) / 0.7).clamp(0.0, 1.0) * 0.45;
              final isActive = t < 0.45;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Transform.translate(
                  offset: Offset(0, -dot * 0.8 * (scale - 0.55)),
                  child: Opacity(
                    opacity: isActive ? 1.0 : 0.35,
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        color: isActive ? base : base.withValues(alpha: 0.25),
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
  final Color? color;

  const SokoVibeThreeDotLoadingPage({
    super.key,
    this.size = 40,
    this.dotSize = 10,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SokoVibeThreeDotLoader(
        size: size,
        dotSize: dotSize,
        color: color,
      ),
    );
  }
}

/// Legacy alias — delegates to [SokoVibeThreeDotLoader] so any remaining
/// usages still render three dots.
class SokoVibeLoading extends StatelessWidget {
  final double size;

  const SokoVibeLoading({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SokoVibeThreeDotLoader(size: size, dotSize: size * 0.25);
  }
}

/// Full-page centered [SokoVibeLoading].
class SokoVibeLoadingPage extends StatelessWidget {
  final double size;

  const SokoVibeLoadingPage({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Center(child: SokoVibeLoading(size: size));
  }
}

/// Legacy alias — delegates to [SokoVibeThreeDotLoader].
class SokoVibeDotLoader extends StatelessWidget {
  final double size;

  const SokoVibeDotLoader({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SokoVibeThreeDotLoader(size: size, dotSize: size * 0.25);
  }
}

/// Full-page centered [SokoVibeDotLoader].
class SokoVibeDotLoadingPage extends StatelessWidget {
  final double size;

  const SokoVibeDotLoadingPage({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Center(child: SokoVibeDotLoader(size: size));
  }
}
