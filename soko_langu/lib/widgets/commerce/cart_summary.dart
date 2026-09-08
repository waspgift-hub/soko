import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Cart summary block: subtotal, delivery, discount and total, plus optional
/// action button.
class CartSummary extends StatelessWidget {
  final double subtotal;
  final double delivery;
  final double discount;
  final Widget? action;
  final String? note;

  const CartSummary({
    super.key,
    required this.subtotal,
    this.delivery = 0,
    this.discount = 0,
    this.action,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (subtotal + delivery - discount).clamp(0, double.infinity).toDouble();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurfaceVariant)),
              Text(context.formatPrice(subtotal), style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurface)),
            ],
          ),
          if (delivery > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Delivery', style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurfaceVariant)),
                Text(context.formatPrice(delivery), style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurface)),
              ],
            ),
          ],
          if (discount > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Discount', style: TextStyle(fontSize: AppFontSize.md, color: cs.successGreen)),
                Text('-${context.formatPrice(discount)}', style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w600, color: cs.successGreen)),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
            child: Divider(color: cs.outlineVariant.withValues(alpha: 0.6), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text(
                context.formatPrice(total),
                style: TextStyle(fontSize: AppFontSize.xl, fontWeight: FontWeight.w700, color: cs.primary),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(note!, style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant)),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.s4),
            action!,
          ],
        ],
      ),
    );
  }
}