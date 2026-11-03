import 'package:flutter/material.dart';

/// Small Soko Vibe brand mark overlaid on product images to deter
/// unauthorised reuse of photos.
class SokoVibeWatermark extends StatelessWidget {
  const SokoVibeWatermark({super.key, this.compact = true, this.opacity = 0.85});

  final bool compact;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 14.0 : 18.0;
    // Product-protection brand mark. Intentional choice: monochrome (single
    // white silhouette, no backdrop box) so it never obscures the photo or
    // fights the color grading — deterrence comes from the mark, not a banner.
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 6),
            child: child,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_rounded,
              size: iconSize,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              'Soko Vibe',
              style: TextStyle(
                fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: opacity),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
