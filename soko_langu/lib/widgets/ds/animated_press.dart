import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
    // Rest state is 0 (scale 1.0); springs drive 0 <-> 1 (rest <-> pressed).
    _controller = AnimationController(
      vsync: this,
      duration: Motion.press,
      reverseDuration: Motion.pressSpringBack,
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Press-in snaps with the standard (controlled) spring; release bounces
  // back with the expressive spring. Springs retarget mid-flight, so a
  // re-press during release never jumps (M3 Expressive motion behavior).
  void _down() {
    if (!widget.enabled) return;
    _controller.animateWith(
      SpringSimulation(
          Motion.standardSpring, _controller.value, 1, 0),
    );
  }

  void _up() {
    if (!widget.enabled) return;
    _controller.animateWith(
      SpringSimulation(
          Motion.expressiveSpring, _controller.value, 0, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final interactive = widget.enabled && widget.onTap != null;
    // Linear mapping: the controller is driven purely by spring simulations,
    // so any extra curve would double-shape the physics output.
    final scale = reduced
        ? const AlwaysStoppedAnimation(1.0)
        : Tween<double>(begin: 1, end: widget.pressedScale)
            .animate(_controller);

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
