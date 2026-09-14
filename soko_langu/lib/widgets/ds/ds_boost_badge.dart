import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../extensions/context_tr.dart';

/// Premium-neutral pill for boosted listings only (spec: boosted = premium
/// but subtle): monochrome chip, no green — green is reserved for commerce
/// and sale states, so boosts stay visually distinct.
class DsBoostBadge extends StatelessWidget {
  final String? label;

  const DsBoostBadge({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white : Colors.black;
    final fg = isDark ? Colors.black : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.82),
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
          Icon(Icons.bolt, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(
            label ?? context.tr('boosted', 'BOOSTED'),
            style: AppTypography.statusChip(fg),
          ),
        ],
      ),
    );
  }
}