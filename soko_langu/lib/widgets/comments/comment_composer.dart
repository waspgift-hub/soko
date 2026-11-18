import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../extensions/context_tr.dart';
import '../../models/comment_model.dart';
import '../../services/comment_service.dart';
import '../../theme/design_tokens.dart';

/// Fixed composer at the bottom of the comments sheet.
///
/// Owns only text entry concerns: multiline input, emoji insertion, `@mention`
/// suggestions and the reply/edit context chip. Submission is the parent's job
/// so it can reconcile the returned comment into its list and never clears the
/// text before the server confirms.
class CommentComposer extends StatefulWidget {
  final CommentService service;
  final String productId;
  final String? avatarUrl;
  final FocusNode focusNode;
  final ProductComment? replyTarget;
  final ProductComment? editing;
  final bool sending;
  final Future<bool> Function(String text, ProductComment? replyTarget, ProductComment? editing) onSubmit;
  final VoidCallback onCancelContext;

  const CommentComposer({
    super.key,
    required this.service,
    required this.productId,
    required this.avatarUrl,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancelContext,
    this.replyTarget,
    this.editing,
    this.sending = false,
  });

  @override
  State<CommentComposer> createState() => CommentComposerState();
}

class CommentComposerState extends State<CommentComposer> {
  static const _emojis = [
    '😀', '😂', '😍', '🥰', '😎', '🤔', '😅', '😢', '😡', '🙏',
    '👍', '👏', '🔥', '❤️', '💯', '✨', '🎉', '👌', '🙌', '💪',
    '😮', '😴', '🤝', '🛒',
  ];

  final TextEditingController _controller = TextEditingController();
  bool _showEmoji = false;
  List<Map<String, dynamic>> _mentionResults = const [];
  String? _mentionQuery;
  Timer? _mentionDebounce;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) _controller.text = editing.text;
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant CommentComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing?.id != oldWidget.editing?.id) {
      _controller.text = widget.editing?.text ?? '';
      if (widget.editing != null) {
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      }
    }
    if (widget.replyTarget?.id != oldWidget.replyTarget?.id && widget.replyTarget != null) {
      widget.focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get hasText => _controller.text.trim().isNotEmpty;

  void _onTextChanged() {
    setState(() {});
    final query = _currentMentionQuery();
    if (query == null) {
      _mentionDebounce?.cancel();
      if (_mentionQuery != null) {
        setState(() {
          _mentionQuery = null;
          _mentionResults = const [];
        });
      }
      return;
    }
    if (query == _mentionQuery) return;
    _mentionQuery = query;
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 250), () async {
      final results = await widget.service.searchMentionUsers(query);
      if (!mounted || _mentionQuery != query) return;
      setState(() => _mentionResults = results);
    });
  }

  String? _currentMentionQuery() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid) return null;
    final cursor = selection.baseOffset.clamp(0, text.length).toInt();
    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    final between = before.substring(at + 1);
    if (between.contains(RegExp(r'\s'))) return null;
    if (between.length > 30) return null;
    return between.toLowerCase();
  }

  void _insertMention(Map<String, dynamic> user) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset.clamp(0, text.length).toInt();
    final at = text.substring(0, cursor).lastIndexOf('@');
    if (at < 0) return;
    final username = (user['username'] ?? '').toString();
    final next = '${text.substring(0, at)}@$username ${text.substring(cursor)}';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + username.length + 2),
    );
    setState(() {
      _mentionQuery = null;
      _mentionResults = const [];
    });
  }

  void _insertEmoji(String emoji) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.sending) return;
    HapticFeedback.lightImpact();
    final ok = await widget.onSubmit(text, widget.replyTarget, widget.editing);
    if (ok && mounted) {
      _controller.clear();
      setState(() {
        _showEmoji = false;
        _mentionQuery = null;
        _mentionResults = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contextLabel = widget.editing != null
        ? context.tr('editing_comment', 'Inahariri maoni')
        : widget.replyTarget != null
            ? '${context.tr('replying_to', 'Unajibu')} @${widget.replyTarget!.userName}'
            : null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mentionResults.isNotEmpty)
            _MentionSuggestions(results: _mentionResults, onPick: _insertMention),
          if (contextLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.sp4, Ds.sp2, Ds.sp4, 0),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      contextLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ds.caption(cs.onSurface).copyWith(color: cs.primary),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onCancelContext,
                    borderRadius: BorderRadius.circular(Ds.rFull),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          if (_showEmoji)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Ds.sp3),
                itemCount: _emojis.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (_, i) => InkWell(
                  onTap: () => _insertEmoji(_emojis[i]),
                  borderRadius: BorderRadius.circular(Ds.rSm),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(_emojis[i], style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.sp3, Ds.sp2, Ds.sp2, Ds.sp2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ComposerAvatar(url: widget.avatarUrl),
                const SizedBox(width: Ds.sp2),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: widget.editing != null
                          ? context.tr('edit_comment_hint', 'Hariri maoni...')
                          : context.tr('comment_hint'),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Ds.rXl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Emoji',
                  onPressed: () => setState(() => _showEmoji = !_showEmoji),
                  icon: Icon(
                    _showEmoji ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (hasText)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: widget.sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: context.tr('send'),
                            onPressed: _submit,
                            icon: Icon(Icons.send_rounded, color: cs.primary),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerAvatar extends StatelessWidget {
  final String? url;
  const _ComposerAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 17,
      backgroundColor: cs.primaryContainer,
      backgroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty)
          ? Icon(Icons.person, size: 18, color: cs.primary)
          : null,
    );
  }
}

class _MentionSuggestions extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final void Function(Map<String, dynamic>) onPick;

  const _MentionSuggestions({required this.results, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length,
        itemBuilder: (_, i) {
          final user = results[i];
          final avatar = (user['avatarUrl'] ?? '').toString();
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: cs.primaryContainer,
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty ? Icon(Icons.person, size: 16, color: cs.primary) : null,
            ),
            title: Text(
              (user['displayName'] ?? user['username'] ?? '').toString(),
              style: Ds.bodySm(cs.onSurface).copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('@${user['username']}', style: Ds.caption(cs.onSurface)),
            onTap: () => onPick(user),
          );
        },
      ),
    );
  }
}
