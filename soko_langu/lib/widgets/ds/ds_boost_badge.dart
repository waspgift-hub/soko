import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';

/// Gold gradient pill for boosted listings only (spec §4.6).
class DsBoostBadge extends StatelessWidget {
  final String label;

  const DsBoostBadge({super.key, this.label = 'BOOSTED'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFB74D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 12, color: Color(0xFF4A2C00)),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTypography.statusChip(const Color(0xFF4A2C00)),
          ),
        ],
      ),
    );
  }
}
