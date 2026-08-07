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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/app_icon.png',
            width: iconSize,
            height: iconSize,
            errorBuilder: (_, _, _) => Icon(
              Icons.storefront,
              size: iconSize,
              color: Colors.white,
            ),
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
    );
  }
}
