import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../extensions/context_tr.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/ds/ds.dart';
import '../boost_tiers.dart';

/// One boost package, rendered as a full-width card.
///
/// Vertical cards rather than the previous three-up row: each tier now carries
/// its own feature list and price-per-day, which a ~110dp column cannot hold
/// without truncating the reason to upgrade.
class BoostTierCard extends StatelessWidget {
  const BoostTierCard({
    super.key,
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final BoostTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedPress(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      pressedScale: 0.985,
      child: AnimatedContainer(
        duration: Motion.cardPress,
        curve: Motion.easeOutCubic,
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: selected
              ? tier.accent.withValues(alpha: 0.07)
              : scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius2.xl),
          border: Border.all(
            color: selected ? tier.accent : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: tier.accent.withValues(alpha: 0.22),
                    blurRadius: 24,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: tier.gradient,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(tier.icon, color: Colors.black, size: 24),
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              context.tr('boost_tier_${tier.key}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.screenTitle(scheme.onSurface)
                                  .copyWith(fontSize: 19),
                            ),
                          ),
                          if (tier.popular) ...[
                            const SizedBox(width: AppSpacing.s2),
                            DsBadge(
                              label: context.tr('boost_most_popular'),
                              color: tier.accent,
                              textColor: Colors.black,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.trParams('boost_days', {
                          'count': '${tier.days}',
                        }),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                _SelectedCheck(selected: selected, accent: tier.accent),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  context.formatPriceInt(
                    tier.price,
                    currencyOverride: 'TZS',
                  ),
                  style: AppTypography.amount(scheme.onSurface).copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    context.trParams('boost_per_day', {
                      'amount': tier.pricePerDay.toStringAsFixed(0),
                    }),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                _SavingTag(tier: tier, selected: selected),
              ],
            ),
            const SizedBox(height: AppSpacing.s3),
            DsDivider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: AppSpacing.s3),
            for (final key in tier.featureKeys)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: selected ? tier.accent : scheme.outline,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        context.tr(key),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectedCheck extends StatelessWidget {
  const _SelectedCheck({required this.selected, required this.accent});

  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.cardPress,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : Colors.transparent,
        border: Border.all(
          color: selected ? accent : scheme.outlineVariant,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15, color: Colors.black)
          : null,
    );
  }
}

/// Bundle saving against buying the same span of days one Bronze day at a time.
/// Hidden on Bronze itself, which *is* the day rate.
class _SavingTag extends StatelessWidget {
  const _SavingTag({required this.tier, required this.selected});

  final BoostTier tier;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final percent = (tier.savingsPercent * 100).round();
    if (percent <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (selected ? tier.accent : scheme.primary)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        context.trParams('boost_save_percent', {'percent': '$percent'}),
        style: AppTypography.statusChip(selected ? tier.accent : scheme.primary),
      ),
    );
  }
}