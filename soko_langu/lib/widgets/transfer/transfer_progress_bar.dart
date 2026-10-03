import 'package:flutter/material.dart';

import '../../services/transfer/transfer_progress.dart';

/// Progress bar that is determinate only when the underlying operation
/// supplied a real denominator.
///
/// The contract with [TransferProgress] is the whole point of this widget: a
/// null fraction renders an indeterminate bar, never a bar parked at 0%. There
/// is no timer, no tween and no eased fake anywhere in this file, so a number
/// that reaches the screen is always a number that came from a byte count or a
/// real state change.
class TransferProgressBar extends StatelessWidget {
  final TransferProgress progress;
  final double height;
  final Color? color;
  final Color? backgroundColor;

  /// Called when the bar is tapped while the transfer has failed and the
  /// failure is retryable.
  final VoidCallback? onRetry;

  const TransferProgressBar({
    super.key,
    required this.progress,
    this.height = 6,
    this.color,
    this.backgroundColor,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = progress.fraction;

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: fraction == null
            ? LinearProgressIndicator(
                // No `value` means indeterminate: the platform sweeps it.
                backgroundColor: backgroundColor ?? cs.surfaceContainerHighest,
                color: color ?? cs.primary,
                minHeight: height,
              )
            : LinearProgressIndicator(
                value: fraction,
                backgroundColor: backgroundColor ?? cs.surfaceContainerHighest,
                color: color ?? cs.primary,
                minHeight: height,
              ),
      ),
    );

    final retryable =
        progress.isFailed && onRetry != null && (progress.failure?.isRetryable ?? false);
    if (!retryable) return bar;

    return InkWell(
      onTap: onRetry,
      borderRadius: BorderRadius.circular(height),
      child: bar,
    );
  }
}

/// One-line status for a transfer: a phase label plus an honest byte readout.
///
/// Shows `2.4 MB / 3.1 MB` when the total is known and `2.4 MB` when it is
/// not, rather than printing a percentage that was never measured.
class TransferStatusLine extends StatelessWidget {
  final TransferProgress progress;
  final String? label;

  const TransferStatusLine({super.key, required this.progress, this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (String text, Color tone) = _describe(theme);
    final percent = progress.percent;

    return Row(
      children: [
        if (label != null) ...[
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (percent != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }

  (String, Color) _describe(ThemeData theme) {
    final cs = theme.colorScheme;
    final bytes = _formatBytes(progress.transferred);

    return switch (progress.phase) {
      TransferPhase.queued => ('Waiting', cs.onSurfaceVariant),
      // No percentage here on purpose: compression duration has nothing to do
      // with how many bytes have been sent.
      TransferPhase.preparing => ('Preparing…', cs.primary),
      TransferPhase.uploading => (
          progress.total == null ? 'Uploading $bytes' : 'Uploading $bytes / ${_formatBytes(progress.total!)}',
          cs.primary,
        ),
      TransferPhase.downloading => (
          progress.total == null ? 'Downloading $bytes' : 'Downloading $bytes / ${_formatBytes(progress.total!)}',
          cs.primary,
        ),
      TransferPhase.processing => ('Processing…', cs.primary),
      TransferPhase.succeeded => (
          progress.total == null ? 'Complete · $bytes' : 'Complete · ${_formatBytes(progress.total!)}',
          _successColor(cs),
        ),
      TransferPhase.cancelled => ('Cancelled', cs.onSurfaceVariant),
      TransferPhase.failed => (
          progress.failure == null
              ? 'Upload failed'
              : 'Failed · ${_describeFailure(progress.failure!)}',
          cs.error,
        ),
    };
  }

  static Color _successColor(ColorScheme cs) =>
      cs.primary; // Kept on-brand; a second green would break the palette.

  /// Short, specific, actionable. Never "something went wrong".
  static String _describeFailure(TransferFailure failure) =>
      switch (failure.kind) {
        TransferFailureKind.offline => 'no connection',
        TransferFailureKind.interrupted => 'connection interrupted',
        TransferFailureKind.cancelled => 'cancelled',
        TransferFailureKind.permissionDenied => 'permission denied',
        TransferFailureKind.tooLarge => 'file too large',
        TransferFailureKind.unsupportedType => 'unsupported file type',
        TransferFailureKind.server => failure.statusCode == null
            ? 'server error'
            : 'server error (${failure.statusCode})',
        TransferFailureKind.authExpired => 'session expired',
        TransferFailureKind.unreadableSource => 'file could not be read',
        TransferFailureKind.unknown => 'upload failed',
      };
}

/// Human byte size. Uses KB/MB rather than KiB/MiB because that is what phone
/// OSes and carriers show, so the number matches what the seller sees in their
/// own settings.
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(bytes >= gb * 10 ? 0 : 1)} GB';
  }
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(bytes >= mb * 10 ? 0 : 1)} MB';
  }
  if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(bytes >= kb * 10 ? 0 : 1)} KB';
  }
  return '$bytes B';
}

/// Exposed so call sites can reuse the exact same formatting.
String formatTransferBytes(int bytes) => _formatBytes(bytes);