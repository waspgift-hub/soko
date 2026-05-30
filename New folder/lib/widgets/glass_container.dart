import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? height;
  final double? width;
  final Color? tintColor;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15,
    this.opacity = 0.15,
    this.borderRadius,
    this.padding,
    this.margin,
    this.height,
    this.width,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? 16;
    final color = tintColor ?? Colors.white;

    return Container(
      height: height,
      width: width,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color.withAlpha((opacity * 255).round()),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withAlpha(60),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
