import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Compact stat block (number + label) for profile and dashboard.
class ProfileStat extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback? onTap;

  const ProfileStat({
    super.key,
    required this.count,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: AppFontSize.xl,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppFontSize.xs, color: cs.onSurfaceVariant),
        ),
      ],
    );

    if (onTap != null) {
      return AnimatedPress(onTap: onTap!, child: child);
    }
    return child;
  }
}