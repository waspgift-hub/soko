import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Payment method selector tile with radio-style selection.
///
/// Displays an icon, label and optional balance; selected state shows a
/// filled primary border and check mark.
class PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  const PaymentMethodTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.selected = false,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedPress(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.06) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, size: 22, color: selected ? cs.primary : cs.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppFontSize.sm, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 22, color: cs.primary)
            else
              Icon(Icons.radio_button_unchecked, size: 22, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }
}