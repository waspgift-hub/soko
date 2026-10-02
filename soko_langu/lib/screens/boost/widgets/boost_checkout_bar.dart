import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/ds/ds.dart';
import '../boost_tiers.dart';

/// Sticky summary + pay bar.
///
/// Pinned to the bottom because the price changes as the seller switches
/// packages, and a seller should never have to scroll back up to confirm what
/// they are about to be charged.
class BoostCheckoutBar extends StatelessWidget {
  const BoostCheckoutBar({
    super.key,
    required this.tier,
    required this.paying,
    required this.enabled,
    required this.onPay,
  });

  final BoostTier tier;
  final bool paying;
  final bool enabled;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceRaised,
        border: Border(top: BorderSide(color: scheme.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: tier.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${context.tr('boost_tier_${tier.key}').toUpperCase()}  •  ${context.trParams('boost_days', {'count': '${tier.days}'})}',
                            style: AppTypography.statusChip(
                              scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.formatPriceInt(
                          tier.price,
                          currencyOverride: 'TZS',
                        ),
                        style: AppTypography.amount(scheme.onSurface)
                            .copyWith(fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: DsButton(
                      label: context.tr('boost_pay_cta'),
                      icon: Icons.bolt_rounded,
                      size: DsButtonSize.lg,
                      height: 54,
                      loading: paying,
                      onPressed: enabled && !paying ? onPay : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    context.tr('boost_secure_note'),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}