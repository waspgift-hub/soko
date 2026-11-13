import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';
import '../models/order_statuses.dart';
import '../theme/app_colors.dart';

class OrderStatusInfo {
  const OrderStatusInfo({
    required this.color,
    required this.icon,
    required this.labelKey,
  });

  final Color color;
  final IconData icon;
  final String labelKey;

  String label(BuildContext context) => context.tr(labelKey);
}

OrderStatusInfo orderStatusInfo(String rawStatus, ColorScheme cs) {
  // Normalize legacy aliases first so both engines render identically.
  final status = canonicalStatusOf(rawStatus);
  switch (status) {
    case OrderStatus.draft:
    case OrderStatus.pending:
    case OrderStatus.published:
      return OrderStatusInfo(
        color: cs.primary,
        icon: Icons.hourglass_empty_rounded,
        labelKey: status == OrderStatus.pending
            ? 'pending'
            : '${status}_label',
      );
    case OrderStatus.addressRequired:
    case OrderStatus.awaitingShippingQuote:
      return OrderStatusInfo(
        color: cs.onSurfaceVariant,
        icon: Icons.rate_review_outlined,
        labelKey: '${status}_label',
      );
    case OrderStatus.pendingShippingFee:
      return OrderStatusInfo(
        color: cs.onSurfaceVariant,
        icon: Icons.local_shipping_outlined,
        labelKey: '${status}_label',
      );
    case OrderStatus.shippingFeeSubmitted:
    case OrderStatus.shippingFeeReview:
    case OrderStatus.quoted:
      return OrderStatusInfo(
        color: cs.tertiary,
        icon: status == OrderStatus.quoted
            ? Icons.description_outlined
            : Icons.receipt_long_outlined,
        labelKey: status == OrderStatus.quoted ? 'quoted' : '${status}_label',
      );
    case OrderStatus.awaitingPayment:
    case OrderStatus.awaitingEscrowPayment:
    case OrderStatus.paymentPending:
      return OrderStatusInfo(
        color: cs.primary,
        icon: Icons.account_balance_wallet_outlined,
        labelKey: status == OrderStatus.awaitingPayment
            ? 'awaiting_payment'
            : '${status}_label',
      );
    case OrderStatus.paymentProcessing:
      return OrderStatusInfo(
        color: cs.primary,
        icon: Icons.account_balance_wallet_outlined,
        labelKey: 'payment_processing_label',
      );
    case OrderStatus.paid:
      return OrderStatusInfo(
        color: cs.primary,
        icon: Icons.payments_outlined,
        labelKey: 'paid',
      );
    case OrderStatus.inEscrow:
      return OrderStatusInfo(
        color: cs.secondary,
        icon: Icons.verified_user_outlined,
        labelKey: 'in_escrow_label',
      );
    case OrderStatus.escrowHeld:
      return OrderStatusInfo(
        color: cs.secondary,
        icon: Icons.verified_user_outlined,
        labelKey: 'escrow_held_label',
      );
    case OrderStatus.sellerAccepted:
      return OrderStatusInfo(
        color: cs.secondary,
        icon: Icons.verified_user_outlined,
        labelKey: 'seller_accepted_label',
      );
    case OrderStatus.dispatchReady:
      return OrderStatusInfo(
        color: cs.secondary,
        icon: Icons.outbox_rounded,
        labelKey: 'dispatch_ready_label',
      );
    case OrderStatus.readyToDispatch:
      return OrderStatusInfo(
        color: cs.secondary,
        icon: Icons.outbox_rounded,
        labelKey: '${status}_label',
      );
    case OrderStatus.disputed:
    case OrderStatus.refundPending:
      return OrderStatusInfo(
        color: cs.error,
        icon: status == OrderStatus.disputed
            ? Icons.gavel_rounded
            : Icons.hourglass_full_rounded,
        labelKey: '${status}_label',
      );
    case OrderStatus.dispatched:
    case OrderStatus.inTransit:
    case OrderStatus.outForDelivery:
    case OrderStatus.deliveryAttempted:
      return OrderStatusInfo(
        color: cs.tertiary,
        icon: status == OrderStatus.dispatched
            ? Icons.local_shipping_outlined
            : Icons.route_rounded,
        labelKey: status == OrderStatus.dispatched
            ? 'dispatched_label'
            : '${status}_label',
      );
    case OrderStatus.arrived:
      return OrderStatusInfo(
        color: cs.tertiary,
        icon: Icons.route_rounded,
        labelKey: 'arrived',
      );
    case OrderStatus.delivered:
      return OrderStatusInfo(
        color: cs.successGreen,
        icon: Icons.inventory_rounded,
        labelKey: 'delivered',
      );
    case OrderStatus.inspectionPeriod:
      return OrderStatusInfo(
        color: cs.successGreen,
        icon: Icons.security_update_good_outlined,
        labelKey: '${status}_label',
      );
    case OrderStatus.otpPending:
      return OrderStatusInfo(
        color: cs.tertiary,
        icon: Icons.pin_rounded,
        labelKey: '${status}_label',
      );
    case OrderStatus.completed:
    case OrderStatus.walletCredited:
    case OrderStatus.payoutPending:
    case OrderStatus.payoutComplete:
      return OrderStatusInfo(
        color: cs.successGreen,
        icon: status == OrderStatus.completed
            ? Icons.check_circle_rounded
            : Icons.account_balance_wallet_outlined,
        labelKey: status == OrderStatus.completed
            ? 'completed'
            : '${status}_label',
      );
    case OrderStatus.cancelled:
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.cancel_rounded,
        labelKey: 'cancelled',
      );
    case OrderStatus.expired:
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.timer_off_rounded,
        labelKey: 'expired',
      );
    case OrderStatus.refunded:
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.replay_rounded,
        labelKey: 'refunded',
      );
    case OrderStatus.failed:
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.error_outline_rounded,
        labelKey: 'failed',
      );
    case OrderStatus.paymentFailed:
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.error_outline_rounded,
        labelKey: 'payment_failed_label',
      );
    default:
      return OrderStatusInfo(
        color: cs.primary,
        icon: Icons.hourglass_empty_rounded,
        labelKey: 'pending',
      );
  }
}

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({
    super.key,
    required this.status,
    this.compact = true,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = orderStatusInfo(status, cs);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: compact ? 12 : 16, color: info.color),
          const SizedBox(width: 4),
          Text(
            info.label(context),
            style: TextStyle(
              fontSize: compact ? 10 : 13,
              fontWeight: FontWeight.w700,
              color: info.color,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderStatusBanner extends StatelessWidget {
  const OrderStatusBanner({
    super.key,
    required this.status,
    this.subtitle,
    this.trailing,
  });

  final String status;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = orderStatusInfo(status, cs);
    final color = info.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.07),
            cs.surface.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Icon(info.icon, size: 24, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.label(context),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
