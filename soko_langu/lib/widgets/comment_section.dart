import 'package:flutter/material.dart';

import '../extensions/context_tr.dart';
import '../models/comment_model.dart';
import '../services/comment_service.dart';
import '../theme/design_tokens.dart';
import 'blue_tick_badge.dart';
import 'comments/comment_sheet.dart';

/// Compact comments preview embedded in Product Detail.
///
/// The full experience lives in [showCommentsSheet]; this widget deliberately
/// stays shallow — two recent comments plus an entry row — so the product page
/// keeps its scroll position and height, and the sheet owns all interaction
/// state (likes, replies, moderation, pagination).
class CommentSection extends StatefulWidget {
  final String productId;

  /// uid of the product's seller, used for the "Seller" tag on the preview.
  final String? sellerId;

  const CommentSection({
    super.key,
    required this.productId,
    this.sellerId,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _service = CommentService();
  late final Stream<CommentPage> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _service.commentsStream(widget.productId);
  }

  void _open({bool focus = false}) {
    showCommentsSheet(
      context,
      productId: widget.productId,
      sellerId: widget.sellerId,
      autofocus: focus,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<CommentPage>(
      stream: _stream,
      builder: (context, snapshot) {
        final page = snapshot.data ?? CommentPage.empty;
        final preview = page.items.take(2).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.sp4, Ds.sp4, Ds.sp4, Ds.sp1),
              child: Row(
                children: [
                  Text(
                    context.tr('comments'),
                    style: Ds.sectionTitle(cs.onSurface).copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  if (page.total > 0) ...[
                    const SizedBox(width: 6),
                    Text('${page.total}', style: Ds.bodySm(cs.onSurface).copyWith(color: cs.onSurfaceVariant)),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: () => _open(),
                    child: Text(context.tr('see_all', 'Ona zote')),
                  ),
                ],
              ),
            ),
            if (preview.isEmpty)
              InkWell(
                onTap: () => _open(focus: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Ds.sp4, vertical: Ds.sp3),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: Ds.sp2),
                      Text(
                        context.tr('no_comments_yet'),
                        style: Ds.bodySm(cs.onSurface).copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              for (final comment in preview)
                _PreviewComment(comment: comment, sellerId: widget.sellerId),
              if (page.items.length > preview.length || page.hasMore)
                InkWell(
                  onTap: () => _open(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Ds.sp4, vertical: Ds.sp2),
                    child: Text(
                      context.tr('view_all_comments', 'Ona maoni yote'),
                      style: Ds.caption(cs.onSurface).copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.sp4, Ds.sp2, Ds.sp4, Ds.sp3),
              child: InkWell(
                onTap: page.commentsEnabled ? () => _open(focus: true) : null,
                borderRadius: BorderRadius.circular(Ds.rFull),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Ds.sp4, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(Ds.rFull),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        page.commentsEnabled ? Icons.edit_outlined : Icons.comments_disabled,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: Ds.sp2),
                      Text(
                        page.commentsEnabled
                            ? context.tr('add_comment', 'Ongeza maoni...')
                            : context.tr('comments_are_off', 'Maoni yamezimwa kwa bidhaa hii.'),
                        style: Ds.bodySm(cs.onSurface).copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PreviewComment extends StatelessWidget {
  final ProductComment comment;
  final String? sellerId;

  const _PreviewComment({required this.comment, this.sellerId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSeller = sellerId != null && sellerId == comment.userId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ds.sp4, Ds.sp2, Ds.sp4, Ds.sp2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            backgroundImage: (comment.userImage != null && comment.userImage!.isNotEmpty)
                ? NetworkImage(comment.userImage!)
                : null,
            child: (comment.userImage == null || comment.userImage!.isEmpty)
                ? Icon(Icons.person, size: 15, color: cs.primary)
                : null,
          ),
          const SizedBox(width: Ds.sp2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ds.caption(cs.onSurface).copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    BlueTickBadge(sellerId: comment.userId, size: 11),
                    if (isSeller) ...[
                      const SizedBox(width: 4),
                      Text(
                        context.tr('seller'),
                        style: Ds.caption(cs.onSurface).copyWith(fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  comment.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Ds.bodySm(cs.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
