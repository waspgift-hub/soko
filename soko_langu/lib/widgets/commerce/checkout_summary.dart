import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Checkout totals block with line items and a fees note.
///
/// [commission] and [paymentFee] are separate lines because Terms 8.2b requires
/// the commission to be shown before payment, and [paymentFee] is the fee
/// ClickPesa actually quoted — the number that leaves the buyer's phone, not an
/// estimate from the local tier table.
class CheckoutSummary extends StatelessWidget {
  final double subtotal;
  final double delivery;
  final double discount;
  final double serviceFee;
  final double commission;
  final double paymentFee;
  final bool quotePending;
  final Widget? action;
  final String? note;

  const CheckoutSummary({
    super.key,
    required this.subtotal,
    this.delivery = 0,
    this.discount = 0,
    this.serviceFee = 0,
    this.commission = 0,
    this.paymentFee = 0,
    this.quotePending = false,
    this.action,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (subtotal + delivery + serviceFee + commission + paymentFee - discount)
        .clamp(0, double.infinity)
        .toDouble();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          _line(context, cs, context.tr('subtotal'), context.formatPrice(subtotal)),
          if (delivery > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(context, cs, context.tr('delivery'), context.formatPrice(delivery)),
          ],
          if (serviceFee > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(context, cs, context.tr('service_fee'), context.formatPrice(serviceFee)),
          ],
          if (commission > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(context, cs, context.tr('soko_vibe_commission'), context.formatPrice(commission)),
          ],
          if (paymentFee > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(
              context,
              cs,
              context.tr('mobile_money_fee', 'Mobile money fee'),
              context.formatPrice(paymentFee),
            ),
          ],
          if (quotePending) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              // Say so rather than silently omitting the fee: an omitted line
              // would leave the buyer to discover the extra debit on their
              // statement.
              context.tr('calculating_payment_fee', 'Calculating mobile money fee...'),
              style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
            ),
          ],
          if (discount > 0) ...[
            const SizedBox(height: AppSpacing.s2),
            _line(
              context,
              cs,
              context.tr('discount'),
              '-${context.formatPrice(discount)}',
              valueColor: cs.successGreen,
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
            child: Divider(color: cs.outlineVariant.withValues(alpha: 0.6), height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.tr('total_payable'), style: TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w700, color: cs.onSurface)),
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