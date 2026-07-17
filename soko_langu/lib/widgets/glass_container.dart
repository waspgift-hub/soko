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
  final bool showReflection;

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
    this.showReflection = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? 16;
    final cs = Theme.of(context).colorScheme;
    final color = tintColor ?? cs.surface;

    return Container(
      height: height,
      width: width,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Stack(
            children: [
              Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: opacity),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: cs.surface.withValues(alpha: 0.24),
                    width: 0.5,
                  ),
                ),
                child: child,
              ),
              // Light reflection overlay
              if (showReflection)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.06),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.03),
                          ],
                          stops: const [0.0, 0.3, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

