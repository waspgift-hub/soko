import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Scroll-entry reveal: opacity 0→1, 24px rise, 0.98→1 scale — once only.
/// Degrades to instant visibility under reduced motion.
class AnimatedReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  /// Fires once when the child first becomes visible (e.g. to start a
  /// section-local animation such as a progress indicator).
  final VoidCallback? onVisible;

  const AnimatedReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.onVisible,
  });

  @override
  State<AnimatedReveal> createState() => _AnimatedRevealState();
}

class _AnimatedRevealState extends State<AnimatedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curve);
    _scale = Tween<double>(begin: 0.98, end: 1).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVisibility(VisibilityInfo info) {
    if (_started || info.visibleFraction < 0.12) return;
    _started = true;
    widget.onVisible?.call();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return VisibilityDetector(
      key: ValueKey('reveal-${widget.child.hashCode}-${widget.delay}'),
      onVisibilityChanged: _onVisibility,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(scale: _scale, child: widget.child),
        ),
      ),
    );
  }
}
