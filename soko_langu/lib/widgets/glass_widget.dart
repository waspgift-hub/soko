import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Reusable glassmorphism widget with fade-in / scale animation.
///
/// Wraps [child] in a frosted-glass container:
/// - Semi-transparent background
/// - Backdrop blur (captures background gradient)
/// - Subtle border & shadow
/// - Delayed fade-in + scale animation
class AnimatedGlassWidget extends StatefulWidget {
  final Widget child;
  final double blurSigma;
  final double opacity;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final double borderWidth;
  final Duration delay;
  final Duration animationDuration;
  final bool noAnimation;

  const AnimatedGlassWidget({
    super.key,
    required this.child,
    this.blurSigma = 8,
    this.opacity = 0.65,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.borderColor,
    this.borderWidth = 0.5,
    this.delay = Duration.zero,
    this.animationDuration = const Duration(milliseconds: 500),
    this.noAnimation = false,
  });

  @override
  State<AnimatedGlassWidget> createState() => _AnimatedGlassWidgetState();
}

class _AnimatedGlassWidgetState extends State<AnimatedGlassWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );

    if (widget.noAnimation) {
      _ctrl.value = 1.0;
    } else if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Timer(widget.delay, () {
        if (mounted) {
          setState(() {});
          _ctrl.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget glass = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          // Backdrop blur — captures gradient behind
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: widget.blurSigma,
                  sigmaY: widget.blurSigma,
                ),
                child: Container(
                  color: cs.surface.withValues(alpha: widget.opacity),
                ),
              ),
            ),
          ),
          // Border overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: widget.borderColor ??
                        Colors.white.withValues(alpha: 0.05),
                    width: widget.borderWidth,
                  ),
                ),
              ),
            ),
          ),
          // Child content
          if (widget.padding != null)
            Padding(padding: widget.padding!, child: widget.child)
          else
            widget.child,
        ],
      ),
    );

    // Wrap in margin if provided
    if (widget.margin != null) {
      glass = Padding(padding: widget.margin!, child: glass);
    }

    // Fade + scale animation
    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (context, child) => Opacity(
        opacity: _fadeAnim.value,
        child: Transform.scale(scale: _scaleAnim.value, child: child),
      ),
      child: glass,
    );
  }
}
