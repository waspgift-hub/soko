import 'package:flutter/material.dart';

class AppAnimations {
  AppAnimations._();
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 350);
  static const Duration slow = Duration(milliseconds: 600);
}

class AnimatedScaleIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double begin;
  final Duration? delay;
  const AnimatedScaleIn({super.key, required this.child, this.duration = const Duration(milliseconds: 300), this.begin = 0.9, this.delay});
  @override
  State<AnimatedScaleIn> createState() => _AnimatedScaleInState();
}
class _AnimatedScaleInState extends State<AnimatedScaleIn> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    if (widget.delay != null) {
      Future.delayed(widget.delay!, () { if (mounted) _ctrl.forward(); });
    } else {
      _ctrl.forward();
    }
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _anim, child: widget.child);
}
