import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';

/// Design-system newline pill for sponsored (ad) listings on feed posts.
class DsAdBadge extends StatelessWidget {
  const DsAdBadge({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(label ?? context.tr('sponsored'), style: AppTypography.statusChip(fg)),
        ],
      ),
    );
  }
}