import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/ds/ds.dart';
import '../boost_tiers.dart';
import 'boost_hero_panel.dart';

/// What the selected package is projected to earn over its full span.
///
/// The figures are derived from the tier's own reach rate rather than being
/// written per tier, and the panel always carries a disclaimer: sellers decide
/// on a projection, but a projection that pretends to be a guarantee loses the
/// sale the moment real numbers land lower.
class BoostReachPanel extends StatelessWidget {
  const BoostReachPanel({super.key, required this.tier});

  final BoostTier tier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tier.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  size: 18,
                  color: tier.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('boost_section_reach'),
                      style: AppTypography.titleSmall(scheme.onSurface),
                    ),
                    Text(
                      context.trParams('boost_reach_window', {
                        'count': '${tier.days}',
                      }),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              DsBadge(
                label: context.tr('estimated'),
                color: scheme.primary,
                textColor: scheme.onPrimary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.visibility_rounded,
                  value: tier.impressions,
                  label: context.tr('boost_reach_impressions'),
                ),
              ),
              Expanded(
                child: _Stat(
                  icon: Icons.touch_app_rounded,
                  value: tier.views,
                  label: context.tr('boost_reach_views'),
                ),
              ),
              Expanded(
                child: _Stat(
                  icon: Icons.chat_bubble_rounded,
                  value: tier.buyerChats,
                  label: context.tr('boost_reach_chats'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          _ComparisonBars(tier: tier),
          const SizedBox(height: AppSpacing.s3),
          Text(
            context.tr('boost_reach_estimate_note'),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(height: 6),
        CountUpText(
          value: value,
          style: AppTypography.amount(scheme.onSurface)
              .copyWith(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

/// Boosted reach against organic reach over the same window. The animated
/// width shift is the single strongest "this is what my money does" moment on
/// the screen, so it is the one comparison drawn.
class _ComparisonBars extends StatelessWidget {
  const _ComparisonBars({required this.tier});

  final BoostTier tier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normal = tier.normalViews.toDouble();
    final boosted = tier.views.toDouble();
    // Both bars are drawn on the same scale (the boosted number) so the
    // shortened organic bar is a truthful ratio, not a second axis.
    final normalFactor = (normal / boosted).clamp(0.05, 1.0);
    final boostedFactor = boosted == 0 ? 0.0 : 1.0;

    return Column(
      children: [
        _Bar(
          label: context.tr('boost_compare_normal'),
          factor: normalFactor,
          color: scheme.outline,
          trailing: '${tier.normalViews}',
        ),
        const SizedBox(height: AppSpacing.s2),
        _Bar(
          label: context.tr('boost_compare_boosted'),
          factor: boostedFactor,
          color: tier.accent,
          trailing: context.trParams('boost_compare_multiplier', {
            'x': tier.viewMultiplier,
          }),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.factor,
    required this.color,
    required this.trailing,
  });

  final String label;
  final double factor;
  final Color color;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: factor),
            duration: Motion.cardEnter,
            curve: Motion.easeOutCubic,
            builder: (context, t, _) => Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: t.clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        SizedBox(
          width: 56,
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            maxLines: 1,
            style: AppTypography.monoLabel(color).copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }
}