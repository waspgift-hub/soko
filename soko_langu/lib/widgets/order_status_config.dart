import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';
import '../models/order_statuses.dart';

class OrderStatusInfo {
  const OrderStatusInfo({required this.color, required this.icon, required this.labelKey});
  final Color color;
  final IconData icon;
  final String labelKey;
  String label(BuildContext context) => context.tr(labelKey);
}

OrderStatusInfo orderStatusInfo(String rawStatus, ColorScheme cs) {
  final status = canonicalStatusOf(rawStatus);
  switch (status) {
    case OrderStatus.awaitingSellerShipping:
      return OrderStatusInfo(color: cs.onSurfaceVariant, icon: Icons.local_shipping_outlined, labelKey: 'awaiting_shipping_quote');
    case OrderStatus.awaitingPayment:
      return OrderStatusInfo(color: cs.primary, icon: Icons.account_balance_wallet_outlined, labelKey: 'awaiting_payment');
    case OrderStatus.paymentProcessing:
      return OrderStatusInfo(color: cs.primary, icon: Icons.sync_rounded, labelKey: 'payment_processing');
    case OrderStatus.paidInEscrow:
      return OrderStatusInfo(color: cs.secondary, icon: Icons.verified_user_outlined, labelKey: 'in_escrow_label');
    case OrderStatus.readyForDispatch:
      return OrderStatusInfo(color: cs.secondary, icon: Icons.outbox_rounded, labelKey: 'ready_to_dispatch_label');
    case OrderStatus.dispatched:
      return OrderStatusInfo(color: cs.tertiary, icon: Icons.local_shipping_outlined, labelKey: 'dispatched_label');
    case OrderStatus.deliveredPendingConfirmation:
      return OrderStatusInfo(color: cs.successGreen, icon: Icons.inventory_rounded, labelKey: 'delivered');
    case OrderStatus.completed:
      return OrderStatusInfo(color: cs.successGreen, icon: Icons.check_circle_rounded, labelKey: 'completed');
    case OrderStatus.paymentFailed:
      return OrderStatusInfo(color: cs.error, icon: Icons.error_outline_rounded, labelKey: 'failed');
    case OrderStatus.cancelled:
      return OrderStatusInfo(color: cs.error, icon: Icons.cancel_rounded, labelKey: 'cancelled');
    case OrderStatus.disputed:
      return OrderStatusInfo(color: cs.error, icon: Icons.gavel_rounded, labelKey: 'disputed_label');
    case OrderStatus.refundPending:
      return OrderStatusInfo(color: cs.error, icon: Icons.hourglass_full_rounded, labelKey: 'refund_pending_label');
    case OrderStatus.refunded:
      return OrderStatusInfo(color: cs.error, icon: Icons.replay_rounded, labelKey: 'refunded');
    case OrderStatus.expired:
      return OrderStatusInfo(color: cs.error, icon: Icons.timer_off_rounded, labelKey: 'expired');
    default:
      return OrderStatusInfo(color: cs.onSurfaceVariant, icon: Icons.help_outline_rounded, labelKey: 'pending');
  }
}

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({super.key, required this.status, this.compact = true});
  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = orderStatusInfo(status, cs);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: info.color.withValues(alpha: 0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(info.icon, size: compact ? 13 : 16, color: info.color),
        const SizedBox(width: 5),
        Text(info.label(context), style: TextStyle(fontSize: compact ? 10.5 : 13, fontWeight: FontWeight.w700, color: info.color)),
      ]),
    );
  }
}

class OrderStatusBanner extends StatelessWidget {
  const OrderStatusBanner({super.key, required this.status, this.subtitle, this.trailing});
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
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(info.icon, size: 23, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.label(context), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.3)),
          ],
        ])),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}
