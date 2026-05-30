import 'package:flutter/material.dart';
import '../main.dart';

class TierBadge extends StatelessWidget {
  final String? tier;
  final double size;
  final bool showLabel;

  const TierBadge({
    super.key,
    this.tier,
    this.size = 16,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = tier ?? themeManager.currentTier;
    if (t == 'free' && !showLabel) return const SizedBox.shrink();

    Color bgColor;
    Color textColor;
    String label;

    switch (t) {
      case 'silver':
        bgColor = Colors.blueGrey;
        textColor = Colors.white;
        label = 'S';
        break;
      case 'premium':
        bgColor = Colors.amber;
        textColor = Colors.white;
        label = 'P';
        break;
      default:
        bgColor = Colors.green;
        textColor = Colors.white;
        label = 'F';
    }

    if (showLabel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bgColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: bgColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              t == 'silver'
                  ? 'Silver'
                  : t == 'premium'
                  ? 'Premium'
                  : 'Free',
              style: TextStyle(
                fontSize: 11,
                color: bgColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.55,
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

