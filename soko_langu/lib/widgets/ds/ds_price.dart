import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_typography.dart';

/// Prominent marketplace price with optional strikethrough old price and
/// computed %OFF badge — one place so every screen prices identically.
class DsPrice extends StatelessWidget {
  final num price;
  final num? oldPrice;
  final String? currencyOverride;
  final bool large;

  const DsPrice({
    super.key,
    required this.price,
    this.oldPrice,
    this.currencyOverride,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDiscount =
        oldPrice != null && oldPrice! > 0 && oldPrice! > price;
    final pct = hasDiscount
        ? ((1 - price / oldPrice!) * 100).round()
        : 0;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          context.formatPrice(price.toDouble(),
              currencyOverride: currencyOverride),
          style: large
              ? AppTypography.amount(cs.primary)
              : AppTypography.amount(cs.onSurface),
        ),
        if (hasDiscount) ...[
          Text(
            context.formatPrice(oldPrice!.toDouble(),
                currencyOverride: currencyOverride),
            style: AppTypography.statusChip(cs.onSurfaceVariant).copyWith(
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '-$pct%',
              style: AppTypography.statusChip(cs.onErrorContainer),
            ),
          ),
        ],
      ],
    );
  }
}
