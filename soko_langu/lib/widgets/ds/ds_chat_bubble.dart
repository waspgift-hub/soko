import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';

/// Generic chat bubble — visual twin of the inbox bubble, usable from chat,
/// AI assistant or anywhere a message row is needed without chat state.
class DsChatBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final String? time;
  final String? imageUrl;
  final VoidCallback? onImageTap;

  const DsChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.time,
    this.imageUrl,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isMe ? cs.primary : cs.surfaceContainerHighest;
    final fg = isMe ? cs.onPrimary : cs.onSurface;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: 4,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.md),
              topRight: const Radius.circular(AppRadius.md),
              bottomLeft: Radius.circular(isMe ? AppRadius.md : 4),
              bottomRight: Radius.circular(isMe ? 4 : AppRadius.md),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageUrl != null && imageUrl!.isNotEmpty)
                GestureDetector(
                  onTap: onImageTap,
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppRadius.sm),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (message.isNotEmpty)
                Text(message, style: AppTypography.appBarTitle(fg)),
              if (time != null && time!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    time!,
                    style: AppTypography.timeIndicator(
                      fg.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
