import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment_model.dart';
import '../services/comment_service.dart';
import '../extensions/context_tr.dart';
import 'google_loading.dart';

class CommentSection extends StatefulWidget {
  final String productId;
  const CommentSection({super.key, required this.productId});

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _commentService = CommentService();
  final _commentController = TextEditingController();
  final _auth = FirebaseAuth.instance;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    if (_auth.currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('login_required'))));
      return;
    }
    await _commentService.addComment(productId: widget.productId, text: text);
    _commentController.clear();
  }

  void _showReplySheet(String commentId) {
    final replyController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: replyController,
                        autofocus: true,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: context.tr('comment_hint'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    sending
                        ? const GoogleLoading(size: 20, strokeWidth: 2)
                        : IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: Color(0xFF2D6A4F),
                            ),
                            onPressed: () async {
                              final text = replyController.text.trim();
                              if (text.isEmpty) return;
                              setSheetState(() => sending = true);
                              await _commentService.addReply(
                                productId: widget.productId,
                                commentId: commentId,
                                text: text,
                              );
                              replyController.clear();
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                context.tr('comments'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D6A4F),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: context.tr('comment_hint'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF2D6A4F)),
                onPressed: _addComment,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<ProductComment>>(
          stream: _commentService.getComments(widget.productId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: GoogleLoading(size: 24, strokeWidth: 2)),
              );
            }
            final comments = snap.data ?? [];
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    context.tr('no_comments_yet'),
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: comments.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = comments[i];
                return _CommentTile(
                  comment: c,
                  productId: widget.productId,
                  onReply: () => _showReplySheet(c.id),
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final ProductComment comment;
  final String productId;
  final VoidCallback onReply;

  const _CommentTile({
    required this.comment,
    required this.productId,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = currentUid == comment.userId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFD8F3DC),
                backgroundImage: comment.userImage != null
                    ? NetworkImage(comment.userImage!)
                    : null,
                child: comment.userImage == null
                    ? Text(
                        comment.userName.isNotEmpty
                            ? comment.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D6A4F),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.userName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF2D6A4F),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTime(comment.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(comment.text, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: onReply,
                          child: Text(
                            context.tr('reply'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF40916C),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (comment.replyCount > 0) ...[
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _showRepliesSheet(context),
                            child: Text(
                              '${comment.replyCount} ${context.tr('replies')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isMine)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (v) {
                    if (v == 'delete') {
                      CommentService().deleteComment(
                        productId: productId,
                        commentId: comment.id,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.tr('delete')),
                    ),
                  ],
                  icon: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRepliesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final replyController = TextEditingController();
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (ctx, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${context.tr('replies')} (${comment.replyCount})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D6A4F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StreamBuilder<List<CommentReply>>(
                      stream: CommentService().getReplies(
                        productId,
                        comment.id,
                      ),
                      builder: (ctx, snap) {
                        final replies = snap.data ?? [];
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: GoogleLoading(size: 24, strokeWidth: 2),
                          );
                        }
                        if (replies.isEmpty) {
                          return Center(
                            child: Text(
                              context.tr('no_comments_yet'),
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: replies.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = replies[i];
                            final isMyReply =
                                FirebaseAuth.instance.currentUser?.uid ==
                                r.userId;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFFD8F3DC),
                                    backgroundImage: r.userImage != null
                                        ? NetworkImage(r.userImage!)
                                        : null,
                                    child: r.userImage == null
                                        ? Text(
                                            r.userName.isNotEmpty
                                                ? r.userName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2D6A4F),
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              r.userName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                                color: Color(0xFF2D6A4F),
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatTime(r.createdAt),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[400],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          r.text,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isMyReply)
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onSelected: (v) {
                                        if (v == 'delete') {
                                          CommentService().deleteReply(
                                            productId: productId,
                                            commentId: comment.id,
                                            replyId: r.id,
                                          );
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(context.tr('delete')),
                                        ),
                                      ],
                                      icon: Icon(
                                        Icons.more_vert,
                                        size: 14,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: replyController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: context.tr('comment_hint'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF2D6A4F)),
                        onPressed: () async {
                          final text = replyController.text.trim();
                          if (text.isEmpty) return;
                          await CommentService().addReply(
                            productId: productId,
                            commentId: comment.id,
                            text: text,
                          );
                          replyController.clear();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
