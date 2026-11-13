import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/transfer/transfer_item.dart';
import '../../services/transfer/transfer_progress.dart';
import '../../theme/design_tokens.dart';
import 'transfer_progress_bar.dart';

/// Per-file rows for a [TransferBatch]: one thumbnail, one honest bar, one
/// status line, one retry button.
///
/// Each row is driven by its own [TransferItem], so a failure shows up on the
/// row that failed while its siblings stay green, and "Retry" re-runs only that
/// file. This is the behaviour a single aggregate progress bar cannot express,
/// and the reason the batch tracks items individually rather than wrapping one
/// `Future.wait`.
class MediaUploadList extends StatelessWidget {
  final TransferBatch batch;
  final String Function(String sourcePath)? labelBuilder;
  final void Function(TransferItem<Object?> item)? onRetry;

  const MediaUploadList({
    super.key,
    required this.batch,
    this.labelBuilder,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: batch.changes,
      builder: (context, _) {
        final items = batch.items;
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.sp2),
                child: MediaUploadRow(
                  key: ValueKey(item.id),
                  item: item,
                  label: labelBuilder?.call(item.sourcePath) ?? item.label,
                  onRetry: onRetry == null ? null : () => onRetry!(item),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A single tracked transfer rendered as a row.
class MediaUploadRow extends StatelessWidget {
  final TransferItem<Object?> item;
  final String label;
  final VoidCallback? onRetry;

  const MediaUploadRow({
    super.key,
    required this.item,
    required this.label,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TransferProgress>(
      stream: item.progress,
      initialData: item.progressSnapshot,
      builder: (context, snapshot) {
        final progress = snapshot.data ?? const TransferProgress.queued();
        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return Container(
          padding: const EdgeInsets.all(Ds.sp3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(Ds.rMd),
            border: Border.all(
              color: progress.isFailed
                  ? cs.error.withValues(alpha: 0.35)
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(sourcePath: item.sourcePath, done: progress.isSucceeded),
              const SizedBox(width: Ds.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TransferStatusLine(progress: progress, label: label),
                    const SizedBox(height: Ds.sp2),
                    if (!progress.isSucceeded)
                      TransferProgressBar(
                        progress: progress,
                        onRetry: progress.isFailed ? onRetry : null,
                      ),
                    if (progress.isFailed && onRetry != null) ...[
                      const SizedBox(height: Ds.sp2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _RetryButton(
                          enabled: progress.failure?.isRetryable ?? false,
                          onPressed: onRetry,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Ds.sp2),
              _StateIcon(progress: progress),
            ],
          ),
        );
      },
    );
  }
}

/// 44px preview of the local file. Decoded straight off disk: this row appears
/// while the bytes are still on the device, so there is nothing to fetch.
class _Thumb extends StatelessWidget {
  final String sourcePath;
  final bool done;

  const _Thumb({required this.sourcePath, required this.done});

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final cs = Theme.of(context).colorScheme;
    final isVideo = _looksLikeVideo(sourcePath);

    return ClipRRect(
      borderRadius: BorderRadius.circular(Ds.rSm),
      child: SizedBox(
        width: size,
        height: size,
        child: isVideo
            ? ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  Icons.videocam_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              )
            : Image.file(
                File(sourcePath),
                fit: BoxFit.cover,
                // Small decode: a grid of these must not pull full-resolution
                // photos into the image cache.
                cacheWidth: 88,
                cacheHeight: 88,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }

  static bool _looksLikeVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.m4v') ||
        p.endsWith('.webm');
  }
}

class _StateIcon extends StatelessWidget {
  final TransferProgress progress;

  const _StateIcon({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 20,
      height: 20,
      child: switch (progress.phase) {
        TransferPhase.succeeded => Icon(Icons.check_circle_rounded,
            size: 20, color: cs.primary),
        TransferPhase.failed =>
          Icon(Icons.error_rounded, size: 20, color: cs.error),
        TransferPhase.cancelled => Icon(Icons.cancel_outlined,
            size: 20, color: cs.onSurfaceVariant),
        TransferPhase.queued => Icon(Icons.schedule_rounded,
            size: 18, color: cs.onSurfaceVariant),
        _ => null,
      },
    );
  }
}

class _RetryButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onPressed;

  const _RetryButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Disabled with no handler rather than hidden: the seller still needs to
    // see that the row failed and that retrying will not help, so the honest
    // state is a visibly inert control, not a vanished one.
    return TextButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(Icons.refresh_rounded, size: 16, color: cs.primary),
      label: Text(
        'Retry',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: enabled ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: Ds.sp2),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}