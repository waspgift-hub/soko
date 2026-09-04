import 'package:flutter/material.dart';

/// Reusable star rating row — replaces hand-drawn stars scattered across
/// seller profile, public profile, analytics and review screens.
class DsRatingStars extends StatelessWidget {
  final double rating;
  final double size;
  final int max;
  final Color? color;

  const DsRatingStars({
    super.key,
    required this.rating,
    this.size = 16,
    this.max = 5,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Colors.amber;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(max, (i) {
        final fill = rating - i;
        final icon = fill >= 1
            ? Icons.star
            : fill >= 0.5
                ? Icons.star_half
                : Icons.star_border;
        return Icon(icon, size: size, color: starColor);
      }),
    );
  }
}
