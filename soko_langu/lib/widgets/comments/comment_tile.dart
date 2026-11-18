import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../models/comment_model.dart';
import '../../theme/design_tokens.dart';
import '../blue_tick_badge.dart';
import '../ds/ds.dart';

/// One comment (or reply) row.
///
/// The tile is deliberately stateless: likes, replies and menus are delegated
/// upward so the sheet keeps a single reconciled copy of every comment and two
/// widgets can never disagree about a like count.
class CommentTile extends StatelessWidget {
  final ProductComment comment;
  final String? sellerId;
  final String? currentUid;
  final bool isProductOwner;
  final bool isModerator;
  final List<ProductComment>? replies;
  final bool repliesOpen;
  final bool repliesLoading;
  final bool busy;
  final VoidCallback onToggleReplies;
  final ValueChanged<ProductComment> onReply;
  final ValueChanged<ProductComment> onLike;
  final ValueChanged<ProductComment> onEdit;
  final ValueChanged<ProductComment> onDelete;
  final ValueChanged<ProductComment> onReport;
  final ValueChanged<ProductComment> onTogglePin;
  final ValueChanged<String> onMentionTap;
  final ValueChanged<ProductComment> onOpenProfile;

  const CommentTile({
    super.key,
    required this.comment,
    this.sellerId,
    this.currentUid,
    this.isProductOwner = false,
    this.isModerator = false,
    this.replies,
    this.repliesOpen = false,
    this.repliesLoading = false,
    this.busy = false,
    required this.onToggleReplies,
    required this.onReply,
    required this.onLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onTogglePin,
    required this.onMentionTap,
    required this.onOpenProfile,
  });

  bool get _isMine => currentUid != null && currentUid == comment.userId;
  bool get _isSellerAuthor => sellerId != null && sellerId == comment.userId;
  bool get _isReply => comment.isReply;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _isReply ? Ds.sp10 : Ds.sp4,
        Ds.sp2,
        Ds.sp2,
        Ds.sp2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => onOpenProfile(comment),
                child: CircleAvatar(
                  radius: _isReply ? 14 : 17,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: (comment.userImage != null && comment.userImage!.isNotEmpty)
                      ? NetworkImage(comment.userImage!)
                      : null,
                  child: (comment.userImage == null || comment.userImage!.isEmpty)
                      ? Icon(Icons.person, size: _isReply ? 15 : 18, color: cs.primary)
                      : null,
                ),
              ),
              const SizedBox(width: Ds.sp2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () => onOpenProfile(comment),
                            child: Text(
                              comment.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                        BlueTickBadge(sellerId: comment.userId, size: 12),
                        if (_isSellerAuthor) ...[
                          const SizedBox(width: 4),
                          _SellerTag(),
                        ],
                        if (comment.pinned) ...[
                          const SizedBox(width: 4),
                          _PinnedTag(),
                        ],
                        const Spacer(),
                        Text(
                          _formatTime(comment.createdAt),
                          style: Ds.caption(cs.onSurface).copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (comment.deleted)
                      Text(
                        context.tr('comment_deleted', 'Maoni yamefutwa'),
                        style: Ds.bodySm(cs.onSurface).copyWith(
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      )
                    else ...[
                      if (comment.replyToUserName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '@${comment.replyToUserName}',
                            style: Ds.caption(cs.onSurface).copyWith(color: cs.primary),
                          ),
                        ),
                      _MentionText(
                        text: comment.text,
                        onMentionTap: onMentionTap,
                        style: Ds.bodyMd(cs.onSurface).copyWith(fontSize: 14),
                      ),
                      if (comment.editedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            context.tr('edited', 'imehaririwa'),
                            style: Ds.caption(cs.onSurface).copyWith(
                              fontSize: 10,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              DsLikeButton(
                                isLiked: comment.likedByMe,
                                size: 17,
                                onPressed: comment.deleted || busy ? null : () => onLike(comment),
                              ),
                              if (comment.likeCount > 0)
                                Text(
                                  _compactCount(comment.likeCount),
                                  style: Ds.caption(cs.onSurface).copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Ds.sp3),
                        InkWell(
                          onTap: comment.deleted ? null : () => onReply(comment),
                          borderRadius: BorderRadius.circular(Ds.rSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: Text(
                              context.tr('reply'),
                              style: Ds.caption(cs.onSurface).copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.tertiary,
                              ),
                            ),
                          ),
                        ),
                        if (!_isReply && comment.replyCount > 0) ...[
                          const SizedBox(width: Ds.sp2),
                          InkWell(
                            onTap: onToggleReplies,
                            borderRadius: BorderRadius.circular(Ds.rSm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              child: Text(
                                repliesOpen
                                    ? context.tr('hide_replies', 'Ficha majibu')
                                    : '${context.tr('view_replies')} (${comment.replyCount})',
                                style: Ds.caption(cs.onSurface).copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        _menu(context),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isReply && repliesOpen)
            Padding(
              padding: const EdgeInsets.only(top: Ds.sp1),
              child: repliesLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final reply in replies ?? const <ProductComment>[])
                          CommentTile(
                            key: ValueKey(reply.id),
                            comment: reply,
                            sellerId: sellerId,
                            currentUid: currentUid,
                            isProductOwner: isProductOwner,
                            isModerator: isModerator,
                            busy: busy,
                            onToggleReplies: onToggleReplies,
                            onReply: onReply,
                            onLike: onLike,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onReport: onReport,
                            onTogglePin: onTogglePin,
                            onMentionTap: onMentionTap,
                            onOpenProfile: onOpenProfile,
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canDelete = _isMine || isProductOwner || isModerator;
    final canPin = !_isReply && (isProductOwner || isModerator);
    final items = <PopupMenuEntry<String>>[
      if (_isMine && !comment.deleted)
        PopupMenuItem(
          value: 'edit',
          child: Text(context.tr('edit', 'Hariri')),
        ),
      if (canPin)
        PopupMenuItem(
          value: 'pin',
          child: Text(comment.pinned
              ? context.tr('unpin_comment', 'Ondoa pini')
              : context.tr('pin_comment', 'Bandika maoni')),
        ),
      if (!_isMine && !comment.deleted)
        PopupMenuItem(
          value: 'report',
          child: Text(context.tr('report_comment', 'Ripoti maoni')),
        ),
      if (canDelete && !comment.deleted)
        PopupMenuItem(
          value: 'delete',
          child: Text(
            context.tr('delete'),
            style: TextStyle(color: cs.error),
          ),
        ),
    ];
    if (items.isEmpty) return const SizedBox(width: 28, height: 28);

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: 16,
      icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
      itemBuilder: (_) => items,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit(comment);
          case 'delete':
            onDelete(comment);
          case 'report':
            onReport(comment);
          case 'pin':
            onTogglePin(comment);
        }
      },
    );
  }

  static String _compactCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }

  static String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 365) return '${(diff.inDays / 7).floor()}w';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Renders comment text with tappable `@mention` runs.
///
/// Recognizers are owned by the State so they are disposed with the widget; a
/// raw TextSpan built in a StatelessWidget would leak one per rebuild.
class _MentionText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final ValueChanged<String> onMentionTap;

  const _MentionText({
    required this.text,
    required this.style,
    required this.onMentionTap,
  });

  @override
  State<_MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<_MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final cs = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(^|\s)@([a-zA-Z0-9_.]{2,30})');
    var index = 0;
    for (final match in pattern.allMatches(widget.text)) {
      final prefix = match.group(1) ?? '';
      final handle = '@${match.group(2)}';
      final start = match.start + prefix.length;
      if (start > index) {
        spans.add(TextSpan(text: widget.text.substring(index, start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onMentionTap(handle.substring(1));
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: handle,
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
        recognizer: recognizer,
      ));
      index = start + handle.length;
    }
    if (index < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(index)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
    );
  }
}

class _SellerTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Ds.rSm),
      ),
      child: Text(
        context.tr('seller'),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary),
      ),
    );
  }
}

class _PinnedTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.push_pin, size: 11, color: cs.tertiary),
        const SizedBox(width: 2),
        Text(
          context.tr('pinned', 'Imebandikwa'),
          style: Ds.caption(cs.onSurface).copyWith(fontSize: 10, color: cs.tertiary),
        ),
      ],
    );
  }
}
