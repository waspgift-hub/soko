import 'package:flutter/material.dart';

/// One-shot fade + slide as a tile enters.
///
/// Cost per instance: one [AnimationController], two [CurvedAnimation]s, two
/// tweens and a [Future.delayed] timer. That is fine for a handful of items and
/// genuinely expensive for a scrolling grid, where dozens mount at once and the
/// animations compete with the scroll for the same frames.
///
/// [enabled] exists so hot paths (product grids, rails) can opt out entirely and
/// still render — the widget becomes a pass-through with no controller, no
/// curves and no timer.
class StaggeredFadeIn extends StatefulWidget {
  const StaggeredFadeIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 300),
    this.enabled = true,
  });

  final Widget child;

  /// Stagger offset in 50ms steps, so a group of items cascades in.
  final int index;

  final Duration duration;

  /// When false the child renders immediately with no animation machinery.
  final bool enabled;

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
      // `mounted` is the guard that matters: the timer can outlive the tile when
      // the user scrolls past it during the stagger delay.
      if (mounted && !_ctrl.isAnimating) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    // Guarded: the controller only exists when the animation is enabled.
    if (widget.enabled) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: widget.child),
    );
  }
}
