import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../theme/app_dimens.dart';
import '../boost_tiers.dart';

/// The full boost menu as a two-column grid, shown above the packages so the
/// seller sees everything a boost can do before choosing how long to run it.
class BoostValuePropGrid extends StatelessWidget {
  const BoostValuePropGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.s3;
        final cellWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final (icon, key) in boostValueProps)
              SizedBox(
                width: cellWidth,
                child: _ValuePropCell(icon: icon, label: context.tr(key)),
              ),
          ],
        );
      },
    );
  }
}

class _ValuePropCell extends StatelessWidget {
  const _ValuePropCell({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 16, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}