import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/comment_model.dart';
import '../../services/comment_service.dart';
import '../../theme/design_tokens.dart';
import 'comment_composer.dart';
import 'comment_tile.dart';

/// Opens the Instagram-style comments sheet for a product.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String productId,
  String? sellerId,
  String? productName,
  bool autofocus = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    enableDrag: true,
    builder: (ctx) {
      final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: DraggableScrollableSheet(
          initialChildSize: 0.93,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          snap: true,
          snapSizes: const [0.93, 0.96],
          expand: false,
          builder: (ctx, scrollController) => CommentsSheet(
            productId: productId,
            sellerId: sellerId,
            productName: productName,
            scrollController: scrollController,
            autofocus: autofocus,
          ),
        ),
      );
    },
  );
}

class CommentsSheet extends StatefulWidget {
  final String productId;
  final String? sellerId;
  final String? productName;
  final ScrollController scrollController;
  final bool autofocus;

  const CommentsSheet({
    super.key,
    required this.productId,
    required this.scrollController,
    this.sellerId,
    this.productName,
    this.autofocus = false,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _service = CommentService();
  final _focusNode = FocusNode();

  final List<ProductComment> _comments = [];
  final Map<String, List<ProductComment>> _replies = {};
  final Set<String> _openReplyIds = {};
  final Set<String> _loadingReplyIds = {};
  final Set<String> _busyIds = {};

  String _sort = 'newest';
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  int _total = 0;
  bool _commentsEnabled = true;

  ProductComment? _replyTarget;
  ProductComment? _editing;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isOwner => widget.sellerId != null && widget.sellerId == _uid;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _loadFirstPage();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    setState(() => _loading = true);
    final page = await _service.fetchComments(widget.productId, sort: _sort);
    if (!mounted) return;
    setState(() {
      _comments
        ..clear()
        ..addAll(page.items);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      _total = page.total;
      _commentsEnabled = page.commentsEnabled;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    final page = await _service.fetchComments(
      widget.productId,
      sort: _sort,
      cursor: _cursor,
    );
    if (!mounted) return;
    setState(() {
      final known = _comments.map((c) => c.id).toSet();
      _comments.addAll(page.items.where((c) => !known.contains(c.id)));
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      if (page.total > 0) _total = page.total;
      _commentsEnabled = page.commentsEnabled;
      _loadingMore = false;
    });
  }

  Future<void> _toggleReplies(ProductComment comment) async {
    if (_openReplyIds.contains(comment.id)) {
      setState(() => _openReplyIds.remove(comment.id));
      return;
    }
    setState(() {
      _openReplyIds.add(comment.id);
      _loadingReplyIds.add(comment.id);
    });
    final replies = await _service.fetchReplies(widget.productId, comment.id);
    if (!mounted) return;
    setState(() {
      _replies[comment.id] = replies;
      _loadingReplyIds.remove(comment.id);
    });
  }

  void _replaceEverywhere(ProductComment updated) {
    var index = _comments.indexWhere((c) => c.id == updated.id);
    if (index >= 0) _comments[index] = updated;
    for (final entry in _replies.entries) {
      final i = entry.value.indexWhere((c) => c.id == updated.id);
      if (i >= 0) entry.value[i] = updated;
    }
  }

  Future<void> _like(ProductComment comment) async {
    if (_busyIds.contains(comment.id)) return;
    final optimistic = comment.copyWith(
      likedByMe: !comment.likedByMe,
      likeCount: (comment.likeCount + (comment.likedByMe ? -1 : 1)).clamp(0, 1 << 30).toInt(),
    );
    setState(() {
      _busyIds.add(comment.id);
      _replaceEverywhere(optimistic);
    });
    try {
      final result = await _service.toggleLike(comment.id);
      if (!mounted) return;
      setState(() {
        _replaceEverywhere(
          optimistic.copyWith(likedByMe: result.liked, likeCount: result.likeCount),
        );
        _busyIds.remove(comment.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replaceEverywhere(comment);
        _busyIds.remove(comment.id);
      });
      _toast(context.tr('like_failed', 'Imeshindikana kupenda'));
    }
  }

  Future<bool> _submit(String text, ProductComment? replyTarget, ProductComment? editing) async {
    if (_sending) return false;
    setState(() => _sending = true);
    try {
      if (editing != null) {
        final updated = await _service.editComment(
          productId: widget.productId,
          commentId: editing.id,
          text: text,
        );
        if (!mounted) return false;
        setState(() {
          if (updated != null) {
            _replaceEverywhere(updated);
          }
          _editing = null;
          _sending = false;
        });
        return true;
      }

      if (replyTarget != null) {
        final created = await _service.addReply(
          productId: widget.productId,
          commentId: replyTarget.parentId ?? replyTarget.id,
          replyToId: replyTarget.id,
          text: text,
        );
        if (!mounted) return false;
        final rootId = replyTarget.parentId ?? replyTarget.id;
        final listIndex = _comments.indexWhere((c) => c.id == rootId);
        if (listIndex >= 0) {
          final root = _comments[listIndex];
          _comments[listIndex] = root.copyWith(replyCount: root.replyCount + 1);
        }
        final existing = _replies[rootId];
        setState(() {
          if (existing != null) {
            existing.add(created);
            // A reply the author just wrote should be visible, not hidden
            // behind a collapsed thread.
            _openReplyIds.add(rootId);
          }
          _replyTarget = null;
          _total = _total + 1;
          _sending = false;
        });
        return true;
      }

      final created = await _service.addComment(productId: widget.productId, text: text);
      if (!mounted) return false;
      setState(() {
        _comments.insert(0, created);
        _total = _total + 1;
        _sending = false;
      });
      // The authoritative ordering is the server's, so re-read rather than
      // guessing where a new comment ranks under "most relevant".
      if (_sort == 'relevant') await _loadFirstPage();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        _toast(e is Exception ? context.trError(e, feature: 'comments') : context.tr('something_wrong'));
      }
      return false;
    }
  }

  Future<void> _delete(ProductComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_comment_title', 'Futa maoni?')),
        content: Text(context.tr('delete_comment_confirm', 'Hatua hii haiwezi kutenduliwa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (comment.isReply) {
        await _service.deleteReply(
          productId: widget.productId,
          commentId: comment.parentId!,
          replyId: comment.id,
        );
        if (!mounted) return;
        setState(() {
          _replies[comment.parentId!]?.removeWhere((c) => c.id == comment.id);
          final i = _comments.indexWhere((c) => c.id == comment.parentId);
          if (i >= 0) {
            final root = _comments[i];
            _comments[i] = root.copyWith(replyCount: (root.replyCount - 1).clamp(0, 1 << 30).toInt());
          }
        });
      } else {
        await _service.deleteComment(productId: widget.productId, commentId: comment.id);
        if (!mounted) return;
        setState(() {
          _comments.removeWhere((c) => c.id == comment.id);
          _replies.remove(comment.id);
          _total = (_total - 1).clamp(0, 1 << 30);
        });
      }
    } catch (e) {
      if (mounted) {
        _toast(e is Exception ? context.trError(e, feature: 'comments') : context.tr('something_wrong'));
      }
    }
  }

  Future<void> _togglePin(ProductComment comment) async {
    setState(() => _busyIds.add(comment.id));
    try {
      await _service.setPinned(commentId: comment.id, pinned: !comment.pinned);
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _comments.length; i++) {
          _comments[i] = _comments[i].copyWith(pinned: _comments[i].id == comment.id && !comment.pinned);
        }
        _busyIds.remove(comment.id);
      });
      await _loadFirstPage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(comment.id));
      _toast(context.tr('pin_failed', 'Imeshindikana kubandika'));
    }
  }

  Future<void> _report(ProductComment comment) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final options = <String, String>{
          'spam': context.tr('report_reason_spam', 'Uchafu / spam'),
          'abuse': context.tr('report_reason_abuse', 'Matusi'),
          'fake': context.tr('report_reason_fake', 'Taarifa za uongo'),
          'other': context.tr('report_reason_other', 'Nyingine'),
        };
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(Ds.rXl),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.tr('report_comment', 'Ripoti maoni'),
                    style: Ds.sectionTitle(cs.onSurface),
                  ),
                ),
                for (final entry in options.entries)
                  ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(ctx, entry.key),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (reason == null) return;
    try {
      await _service.reportComment(commentId: comment.id, reason: reason);
      if (mounted) _toast(context.tr('report_sent', 'Ripoti imetumwa. Asante!'));
    } catch (_) {
      if (mounted) _toast(context.tr('something_wrong'));
    }
  }

  Future<void> _openProfile(ProductComment comment) async {
    if (comment.userId.isEmpty) return;
    context.push('${AppRoutes.publicProfile}/${comment.userId}', extra: comment.userName);
  }

  Future<void> _openMention(String handle) async {
    final user = await _service.findUserByUsername(handle);
    if (!mounted) return;
    if (user == null) {
      _toast(context.tr('user_not_found', 'Mtumiaji hajapatikana'));
      return;
    }
    context.push(
      '${AppRoutes.publicProfile}/${user['userId']}',
      extra: (user['displayName'] ?? '').toString(),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _startReply(ProductComment comment) {
    setState(() {
      _editing = null;
      _replyTarget = comment;
    });
    _focusNode.requestFocus();
  }

  void _startEdit(ProductComment comment) {
    setState(() {
      _replyTarget = null;
      _editing = comment;
    });
    _focusNode.requestFocus();
  }

  Future<void> _toggleCommentsEnabled() async {
    final next = !_commentsEnabled;
    setState(() => _commentsEnabled = next);
    try {
      await _service.setCommentsEnabled(productId: widget.productId, enabled: next);
      if (!mounted) return;
      _toast(
        next
            ? context.tr('comments_enabled', 'Maoni yamewashwa')
            : context.tr('comments_disabled', 'Maoni yamezimwa'),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsEnabled = !next);
      _toast(context.tr('something_wrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? Colors.black : Colors.white;
    final avatar = FirebaseAuth.instance.currentUser?.photoURL;

    return Material(
      color: background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(Ds.rXl)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _Handle(),
          _Header(
            total: _total,
            sort: _sort,
            isOwner: _isOwner,
            commentsEnabled: _commentsEnabled,
            onToggleComments: _isOwner ? _toggleCommentsEnabled : null,
            onSortChanged: (value) {
              if (value == _sort) return;
              setState(() => _sort = value);
              _loadFirstPage();
            },
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
          Expanded(child: _buildBody(cs)),
          SafeArea(
            top: false,
            child: _commentsEnabled
                ? CommentComposer(
                    service: _service,
                    productId: widget.productId,
                    avatarUrl: avatar,
                    focusNode: _focusNode,
                    replyTarget: _replyTarget,
                    editing: _editing,
                    sending: _sending,
                    onSubmit: _submit,
                    onCancelContext: () => setState(() {
                      _replyTarget = null;
                      _editing = null;
                    }),
                  )
                : _CommentsOffBanner(isOwner: _isOwner, onEnable: _toggleCommentsEnabled),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_comments.isEmpty) {
      return ListView(
        controller: widget.scrollController,
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          Icon(Icons.chat_bubble_outline, size: 44, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              context.tr('no_comments_yet'),
              style: Ds.bodySm(cs.onSurface).copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              context.tr('be_first_comment', 'Anza mazungumzo!'),
              style: Ds.caption(cs.onSurface),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: Ds.sp4),
      itemCount: _comments.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _comments.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final comment = _comments[index];
        return CommentTile(
          key: ValueKey(comment.id),
          comment: comment,
          sellerId: widget.sellerId,
          currentUid: _uid,
          isProductOwner: _isOwner,
          isModerator: false,
          replies: _replies[comment.id],
          repliesOpen: _openReplyIds.contains(comment.id),
          repliesLoading: _loadingReplyIds.contains(comment.id),
          busy: _busyIds.contains(comment.id),
          onToggleReplies: () => _toggleReplies(comment),
          onReply: _startReply,
          onLike: _like,
          onEdit: _startEdit,
          onDelete: _delete,
          onReport: _report,
          onTogglePin: _togglePin,
          onMentionTap: _openMention,
          onOpenProfile: _openProfile,
        );
      },
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(Ds.rFull),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final String sort;
  final bool isOwner;
  final bool commentsEnabled;
  final VoidCallback? onToggleComments;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onClose;

  const _Header({
    required this.total,
    required this.sort,
    required this.isOwner,
    required this.commentsEnabled,
    required this.onSortChanged,
    required this.onClose,
    this.onToggleComments,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ds.sp4, 2, Ds.sp2, Ds.sp2),
      child: Row(
        children: [
          Text(
            context.tr('comments'),
            style: Ds.sectionTitle(cs.onSurface).copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (total > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$total',
              style: Ds.bodySm(cs.onSurface).copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: sort,
            onSelected: onSortChanged,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'relevant',
                child: Row(
                  children: [
                    if (sort == 'relevant') Icon(Icons.check, size: 16, color: cs.primary),
                    if (sort == 'relevant') const SizedBox(width: 6),
                    Text(context.tr('most_relevant', 'Muhimu zaidi')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'newest',
                child: Row(
                  children: [
                    if (sort == 'newest') Icon(Icons.check, size: 16, color: cs.primary),
                    if (sort == 'newest') const SizedBox(width: 6),
                    Text(context.tr('newest', 'Mpya zaidi')),
                  ],
                ),
              ),
            ],
            icon: Icon(Icons.sort, size: 20, color: cs.onSurfaceVariant),
            tooltip: context.tr('sort_comments', 'Panga maoni'),
          ),
          if (isOwner)
            PopupMenuButton<String>(
              onSelected: (_) => onToggleComments?.call(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(
                    children: [
                      Icon(
                        commentsEnabled ? Icons.comments_disabled : Icons.chat_bubble_outline,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        commentsEnabled
                            ? context.tr('turn_off_comments', 'Zima maoni')
                            : context.tr('turn_on_comments', 'Washa maoni'),
                      ),
                    ],
                  ),
                ),
              ],
              icon: Icon(Icons.tune, size: 20, color: cs.onSurfaceVariant),
              tooltip: context.tr('comment_settings', 'Mipangilio ya maoni'),
            ),
          IconButton(
            onPressed: onClose,
            tooltip: context.tr('close', 'Funga'),
            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CommentsOffBanner extends StatelessWidget {
  final bool isOwner;
  final VoidCallback onEnable;

  const _CommentsOffBanner({required this.isOwner, required this.onEnable});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Ds.sp4, Ds.sp3, Ds.sp4, Ds.sp3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: Row(
        children: [
          Icon(Icons.comments_disabled, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: Ds.sp2),
          Expanded(
            child: Text(
              context.tr('comments_are_off', 'Maoni yamezimwa kwa bidhaa hii.'),
              style: Ds.bodySm(cs.onSurface).copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          if (isOwner)
            TextButton(
              onPressed: onEnable,
              child: Text(context.tr('turn_on_comments', 'Washa maoni')),
            ),
        ],
      ),
    );
  }
}
