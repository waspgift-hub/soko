import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Raised as a floating banner at the bottom via `ScaffoldMessenger`, sharing
/// one look for success/info/danger so every notification is unmistakably Soko.
///
/// Use [SokoSnackbar.show] instead of raw `SnackBar` for consistent chrome:
/// icon, message, optional action and rounded surface instead of the default.
class SokoSnackbar {
  SokoSnackbar._();

  static void show(
    BuildContext context, {
    required String message,
    SokoSnackType type = SokoSnackType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    final color = _colorFor(context, type);
    // surface background so the message reads clearly at any theme brightness
    final bg = Theme.of(context).colorScheme.surface;
    final fg = Theme.of(context).colorScheme.onSurface;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(_iconFor(type), size: 20, color: color),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg),
                ),
              ),
            ],
          ),
          backgroundColor: bg,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: color.withValues(alpha: 0.35)),
          ),
          action: actionLabel != null
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: color,
                  onPressed: onAction ?? () {},
                )
              : null,
        ),
      );
  }

  static IconData _iconFor(SokoSnackType type) {
    switch (type) {
      case SokoSnackType.success:
        return Icons.check_circle_rounded;
      case SokoSnackType.error:
        return Icons.error_rounded;
      case SokoSnackType.warning:
        return Icons.warning_amber_rounded;
      case SokoSnackType.info:
        return Icons.info_rounded;
    }
  }

  static Color _colorFor(BuildContext context, SokoSnackType type) {
    final cs = Theme.of(context).colorScheme;
    switch (type) {
      case SokoSnackType.success:
        return cs.successGreen;
      case SokoSnackType.error:
        return cs.error;
      case SokoSnackType.warning:
        return Theme.of(context).colorScheme.brandTextSecondary;
      case SokoSnackType.info:
        return cs.primary;
    }
  }

  static void success(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message: message, type: SokoSnackType.success, actionLabel: actionLabel, onAction: onAction);
  static void error(BuildContext context, String message) =>
      show(context, message: message, type: SokoSnackType.error);
  static void info(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message: message, type: SokoSnackType.info, actionLabel: actionLabel, onAction: onAction);
}

enum SokoSnackType { success, error, warning, info }