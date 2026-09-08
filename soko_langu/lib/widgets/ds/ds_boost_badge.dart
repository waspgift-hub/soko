import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../extensions/context_tr.dart';

/// Monochrome pill for boosted listings only (spec §4.6): solid primary chip,
/// no gold gradient.
class DsBoostBadge extends StatelessWidget {
  final String? label;

  const DsBoostBadge({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 12, color: cs.onPrimary),
          const SizedBox(width: 3),
          Text(
            label ?? context.tr('boosted', 'BOOSTED'),
            style: AppTypography.statusChip(cs.onPrimary),
          ),
        ],
      ),
    );
  }
}