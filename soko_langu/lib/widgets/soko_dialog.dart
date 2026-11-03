import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'ds/ds.dart';

enum SokoDialogVariant { info, confirm, danger }

/// Result of a confirm dialog.
class SokoDialogResult {
  final bool confirmed;
  final String? action;
  const SokoDialogResult({required this.confirmed, this.action});
}

/// Branded alert/confirm dialog with a title, message and action buttons.
///
/// [SokoDialog.show] returns whether the primary action was chosen, so callers
/// can branch on confirmation without reading screens.
class SokoDialog extends StatelessWidget {
  final SokoDialogVariant variant;
  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool showCancel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const SokoDialog({
    super.key,
    this.variant = SokoDialogVariant.info,
    this.icon = Icons.info_outline_rounded,
    required this.title,
    required this.message,
    this.confirmLabel = 'OK',
    this.cancelLabel = 'Cancel',
    this.showCancel = true,
    this.onConfirm,
    this.onCancel,
  });

  /// Presents the dialog and resolves `true` when the user confirms.
  static Future<bool> show(
    BuildContext context, {
    SokoDialogVariant variant = SokoDialogVariant.info,
    IconData icon = Icons.info_outline_rounded,
    required String title,
    required String message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool showCancel = true,
  }) async {
    final result = await showDialog<SokoDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SokoDialog(
        variant: variant,
        icon: icon,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        showCancel: showCancel,
        onConfirm: () => Navigator.of(context).pop(const SokoDialogResult(confirmed: true)),
        onCancel: () => Navigator.of(context).pop(const SokoDialogResult(confirmed: false)),
      ),
    );
    return result?.confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _accent(variant, cs);

    return Dialog(
      backgroundColor: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s5),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.s3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: accent),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: AppSpacing.s5),
            Row(
              children: [
                if (showCancel) ...[
                  Expanded(
                    child: DsButton(
                      onPressed: onCancel,
                      variant: DsButtonVariant.tonal,
                      size: DsButtonSize.md,
                      label: cancelLabel,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                ],
                Expanded(
                  child: DsButton(
                    onPressed: onConfirm,
                    variant: variant == SokoDialogVariant.danger
                        ? DsButtonVariant.danger
                        : DsButtonVariant.primary,
                    size: DsButtonSize.md,
                    label: confirmLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _accent(SokoDialogVariant variant, ColorScheme cs) {
    switch (variant) {
      case SokoDialogVariant.info:
        return cs.primary;
      case SokoDialogVariant.confirm:
        return cs.successGreen;
      case SokoDialogVariant.danger:
        return cs.error;
    }
  }
}