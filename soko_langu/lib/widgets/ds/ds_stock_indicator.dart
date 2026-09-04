import 'package:flutter/material.dart';

/// Stock availability line: green when plentiful, amber when low.
/// Shows "Only X left" at or below [lowThreshold] to create urgency
/// without ever displaying a negative or misleading number.
class DsStockIndicator extends StatelessWidget {
  final int stock;
  final int lowThreshold;

  const DsStockIndicator({
    super.key,
    required this.stock,
    this.lowThreshold = 5,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (stock <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_shopping_cart_outlined,
              size: 14, color: cs.error),
          const SizedBox(width: 4),
          Text('Out of stock',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.error)),
        ],
      );
    }
    final low = stock <= lowThreshold;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          low
              ? Icons.local_fire_department_outlined
              : Icons.check_circle_outline,
          size: 14,
          color: low ? cs.tertiary : cs.primary,
        ),
        const SizedBox(width: 4),
        Text(
          low ? 'Only $stock left' : 'In stock ($stock)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: low ? cs.tertiary : cs.primary,
          ),
        ),
      ],
    );
  }
}
