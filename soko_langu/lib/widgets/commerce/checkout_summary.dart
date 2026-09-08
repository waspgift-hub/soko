import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Checkout totals block with line items and a fees note.
class CheckoutSummary extends StatelessWidget {
  final double subtotal;
  final double delivery;
  final double discount;
  final double serviceFee;
  final Widget? action;
  final String? note;

  const CheckoutSummary({
    super.key,
    required this.subtotal,
    this.delivery = 0,
    this.discount = 0,
    this.serviceFee = 0,
    this.action,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (subtotal + delivery + serviceFee - discount).clamp(0, double.infinity).toDouble();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          _line(context, cs, 'Subtotal', context.formatPrice(subtotal)),
          if (delivery > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(context, cs, 'Delivery', context.formatPrice(delivery)),
          ],
          if (serviceFee > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(context, cs, 'Service fee', context.formatPrice(serviceFee)),
          ],
          if (discount > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(context, cs, 'Discount', '-${context.formatPrice(discount)}', valueColor: cs.successGreen),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
            child: Divider(color: cs.outlineVariant.withValues(alpha: 0.6), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total payable', style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text(
                context.formatPrice(total),
                style: TextStyle(fontSize: AppFontSize.xl, fontWeight: FontWeight.w700, color: cs.primary),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              note!,
              style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.s4),
            action!,
          ],
        ],
      ),
    );
  }

  Widget _line(BuildContext context, ColorScheme cs, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurfaceVariant)),
        Text(
          value,
          style: TextStyle(
            fontSize: AppFontSize.md,
            fontWeight: FontWeight.w600,
            color: valueColor ?? cs.onSurface,
          ),
        ),
      ],
    );
  }
}