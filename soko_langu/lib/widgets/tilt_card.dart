import 'package:flutter/material.dart';
import '../../main.dart';

class TiltCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double tiltFactor;

  const TiltCard({
    super.key,
    required this.child,
    this.onTap,
    this.tiltFactor = 0.03,
  });

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _isPressed = true;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _isPressed = false;
    _controller.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _isPressed = false;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.of(context);
    final isSilver = config.accountTier == 'silver';
    final scale = _scaleAnimation.value;

    final transform = Matrix4.diagonal3Values(scale, scale, scale);
    if (_isPressed && isSilver) {
      transform.setEntry(3, 2, 0.001);
      transform.rotateX(0.02);
      transform.rotateY(-0.02);
    }

    return Transform(
      transform: transform,
      alignment: FractionalOffset.center,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: widget.child,
        ),
      ),
    );
  }
}
