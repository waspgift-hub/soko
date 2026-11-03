import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';

/// Scale-on-press wrapper (1.0 → 0.97 → spring back) used by every ds control.
///
/// Respects `MediaQuery.disableAnimations` by degrading to a plain tap.
class AnimatedPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double pressedScale;

  const AnimatedPress({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.press,
      reverseDuration: Motion.pressSpringBack,
      value: 1,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down() {
    if (widget.enabled) _controller.forward();
  }

  void _up() {
    if (widget.enabled && _controller.isForwardOrCompleted) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final interactive = widget.enabled && widget.onTap != null;
    final scale = reduced
        ? const AlwaysStoppedAnimation(1.0)
        : Tween<double>(begin: 1, end: widget.pressedScale).animate(
            CurvedAnimation(parent: _controller, curve: Motion.easeOutCubic),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: interactive ? (_) => _down() : null,
      onTapUp: interactive ? (_) => _up() : null,
      onTapCancel: interactive ? _up : null,
      onTap: widget.onTap,
      child: ScaleTransition(scale: scale, child: widget.child),
    );
  }
}
