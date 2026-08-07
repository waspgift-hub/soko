import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';
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

OrderStatusInfo orderStatusInfo(String status, ColorScheme cs) {
  switch (status) {
    case 'awaiting_shipping_quote':
      return const OrderStatusInfo(
        color: Color(0xFFF59E0B),
        icon: Icons.rate_review_outlined,
        labelKey: 'awaiting_shipping_quote_label',
      );
    case 'awaiting_payment':
      return const OrderStatusInfo(
        color: Color(0xFF3B82F6),
        icon: Icons.account_balance_wallet_outlined,
        labelKey: 'awaiting_payment',
      );
    case 'quoted':
      return const OrderStatusInfo(
        color: Color(0xFF14B8A6),
        icon: Icons.description_outlined,
        labelKey: 'quoted',
      );
    case 'paid':
      return const OrderStatusInfo(
        color: Color(0xFF4F46E5),
        icon: Icons.payments_outlined,
        labelKey: 'paid',
      );
    case 'escrow_hold':
    case 'paid_escrow_hold':
    case 'paid_escrow_held':
      return const OrderStatusInfo(
        color: Color(0xFF9333EA),
        icon: Icons.verified_user_outlined,
        labelKey: 'secured_in_escrow',
      );
    case 'dispatched':
      return const OrderStatusInfo(
        color: Color(0xFFF97316),
        icon: Icons.local_shipping_outlined,
        labelKey: 'dispatched_label',
      );
    case 'delivered':
    case 'delivery_confirmed':
      return OrderStatusInfo(
        color: cs.successGreen,
        icon: Icons.inventory_rounded,
        labelKey: 'delivered',
      );
    case 'confirmed':
      return OrderStatusInfo(
        color: cs.tertiary,
        icon: Icons.verified_outlined,
        labelKey: 'confirmed',
      );
    case 'completed':
      return OrderStatusInfo(
        color: cs.successGreen,
        icon: Icons.check_circle_rounded,
        labelKey: 'completed',
      );
    case 'cancelled':
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.cancel_rounded,
        labelKey: 'cancelled',
      );
    case 'refunded':
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.replay_rounded,
        labelKey: 'refunded',
      );
    case 'failed':
      return OrderStatusInfo(
        color: cs.error,
        icon: Icons.error_outline_rounded,
        labelKey: 'failed',
      );
    case 'pending':
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
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(info.icon, size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.label(context),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
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
