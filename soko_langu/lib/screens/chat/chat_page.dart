import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import '../../services/chat_typing.dart';
import '../../services/user_service.dart';
import '../../services/whatsapp_service.dart';
import '../../models/message_model.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String productName;
  final String? productId;

  const ChatPage({
    super.key,
    required this.receiverId,
    this.receiverName = '',
    this.productName = '',
    this.productId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatService _chatService = ChatService();
  final ChatTyping _chatTyping = ChatTyping();
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final UserService _userService = UserService();
  List<Message> _messages = [];
  bool _isTyping = false;
  bool _otherTyping = false;
  String? _replyTo;
  String? _replyToContent;
  String? _replyToSender;
  Timer? _typingTimer;
  bool _autoScrolling = false;
  String? _receiverPhone;
  String? _receiverPhoto;
  StreamSubscription<UserProfile?>? _profileSub;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _roomId => _chatService.roomIdFor(_uid, widget.receiverId);

  StreamSubscription<bool>? _typingSub;

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(_roomId);
    _inputCtrl.addListener(_onInputChanged);
    _fetchReceiverPhone();
    _typingSub = _chatTyping.observeTyping(widget.receiverId).listen((t) {
      if (mounted) setState(() => _otherTyping = t);
    });
  }

  Future<void> _fetchReceiverPhone() async {
    final profile = await _userService.getProfile(widget.receiverId);
    if (mounted && profile != null) {
      setState(() {
        _receiverPhone = profile.phone;
        _receiverPhoto = profile.profileImage;
      });
    }
    _profileSub = _userService.streamProfile(widget.receiverId).listen((p) {
      if (!mounted) return;
      setState(() {
        if (p != null) {
          _receiverPhone = p.phone;
          _receiverPhoto = p.profileImage;
        }
      });
    });
  }

  void _openWhatsApp() {
    final phone = _receiverPhone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('phone_not_found'))),
      );
      return;
    }
    final msg = WhatsAppService.generateProfileMessage(
      sellerName: widget.receiverName,
    );
    WhatsAppService().openWhatsApp(phoneNumber: phone, message: msg);
  }

  @override
  void dispose() {
    _typingSub?.cancel();
    _profileSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _chatTyping.stopTyping(widget.receiverId);
    super.dispose();
  }

  void _onInputChanged() {
    if (_inputCtrl.text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      _chatTyping.startTyping(widget.receiverId);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        _chatTyping.stopTyping(widget.receiverId);
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _chatService.sendMessage(
      receiverId: widget.receiverId,
      content: text,
      productId: widget.productId,
      productName: widget.productName,
      replyTo: _replyTo,
      replyToContent: _replyToContent,
      replyToSender: _replyToSender,
    );
    _inputCtrl.clear();
    _replyTo = null;
    _replyToContent = null;
    _replyToSender = null;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    _autoScrolling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      _autoScrolling = false;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFE5DDD5),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black12,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : const Color(0xFF3B4A54)),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => context.push('${AppRoutes.publicProfile}/${widget.receiverId}',
              extra: widget.receiverName),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                backgroundImage: _receiverPhoto != null && _receiverPhoto!.isNotEmpty
                    ? NetworkImage(_receiverPhoto!)
                    : null,
                child: _receiverPhoto == null || _receiverPhoto!.isEmpty
                    ? Text(widget.receiverName.isNotEmpty
                        ? widget.receiverName[0].toUpperCase()
                        : '?',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.receiverName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF111B21),
                        ),
                        overflow: TextOverflow.ellipsis),
                    if (_otherTyping)
                      Text(context.tr('typing'),
                          style: TextStyle(fontSize: 12, color: cs.primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            tooltip: context.tr('whatsapp'),
            onPressed: _openWhatsApp,
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: isDark ? Colors.white : const Color(0xFF3B4A54)),
            onPressed: () => _showOptions(cs),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _chatService.getMessages(_roomId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: GoogleLoading());
                }
                final msgs = snap.data ?? [];
                if (msgs != _messages) {
                  _messages = msgs;
                  if (!_autoScrolling) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollCtrl.hasClients) {
                        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                      }
                    });
                  }
                }
                if (msgs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: cs.primary.withValues(alpha: 0.08),
                          child: Icon(Icons.chat_outlined, size: 40, color: cs.primary.withValues(alpha: 0.4)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('no_messages_yet'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('send_first_message'),
                          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                        if (widget.productName.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shopping_bag, size: 14, color: cs.primary),
                                const SizedBox(width: 6),
                                Text(widget.productName,
                                  style: TextStyle(fontSize: 13, color: cs.primary),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () => _focusNode.unfocus(),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final msg = msgs[i];
                      final isFirstOfDay = i == msgs.length - 1 ||
                          !_isSameDay(msg.timestamp, msgs[i + 1].timestamp);
                      final showTime = i == 0 ||
                          msgs[i - 1].senderId != msg.senderId ||
                          msgs[i - 1].timestamp.difference(msg.timestamp).abs() >
                              const Duration(minutes: 5);

                      return Column(
                        children: [
                          if (isFirstOfDay) _dateSeparator(msg.timestamp, cs),
                          _MessageBubble(
                            message: msg,
                            isMe: msg.senderId == _uid,
                            showTime: showTime,
                            onReply: msg.content == 'deleted' || msg.isDeletedForEveryone
                                ? null
                                : () {
                                    final isMe = msg.senderId == _uid;
                                    _replyTo = msg.id;
                                    _replyToContent = msg.content;
                                    _replyToSender = isMe
                                        ? (FirebaseAuth.instance.currentUser?.displayName ?? context.tr('you'))
                                        : widget.receiverName;
                                    _focusNode.requestFocus();
                                    setState(() {});
                                  },
                            onReact: (emoji) {
                              _chatService.addReaction(
                                otherUserId: widget.receiverId,
                                messageId: msg.id,
                                emoji: emoji,
                              );
                            },
                            cs: cs,
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // Reply preview
          if (_replyTo != null)
            Container(
              color: isDark ? const Color(0xFF1F2C33) : Colors.white,
              padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
              child: Row(
                children: [
                  Container(width: 4, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_replyToSender ?? '',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600)),
                          Text(_replyToContent ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _replyTo = null;
                      _replyToContent = null;
                      _replyToSender = null;
                    }),
                  ),
                ],
              ),
            ),
          // Input bar
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2C33) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
              top: 8,
            ),
            child: Row(
              children: [
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: context.tr('type_message'),
                      hintStyle: TextStyle(color: const Color(0xFF8696A0), fontSize: 15),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A3942) : const Color(0xFFF0F2F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: Icon(Icons.emoji_emotions_outlined, size: 22, color: const Color(0xFF8696A0)),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.attach_file, size: 22, color: const Color(0xFF8696A0)),
                          const SizedBox(width: 4),
                          Icon(Icons.camera_alt_outlined, size: 22, color: const Color(0xFF8696A0)),
                          const SizedBox(width: 4),
                        ],
                      ),
                      suffixIconConstraints: const BoxConstraints(minWidth: 60, minHeight: 0),
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : const Color(0xFF111B21),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF075E54),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateSeparator(DateTime dt, ColorScheme cs) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(dt, now)) {
      label = context.tr('today');
    } else if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) {
      label = context.tr('yesterday');
    } else {
      label = '${dt.day}/${dt.month}/${dt.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }

  void _showOptions(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(context.tr('view_profile')),
              onTap: () {
                Navigator.pop(ctx);
                context.push('${AppRoutes.publicProfile}/${widget.receiverId}',
                    extra: widget.receiverName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(context.tr('block')),
              onTap: () async {
                Navigator.pop(ctx);
                await _chatService.blockUser(widget.receiverId);
                if (mounted) context.pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(context.tr('delete_conversation')),
              onTap: () async {
                Navigator.pop(ctx);
                await _chatService.deleteConversation(widget.receiverId);
                if (mounted) context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showTime;
  final VoidCallback? onReply;
  final void Function(String emoji) onReact;
  final ColorScheme cs;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showTime,
    this.onReply,
    required this.onReact,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final isDeleted = message.content == 'deleted' || message.isDeletedForEveryone;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Message bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: EdgeInsets.only(
              left: 14, right: 14,
              top: message.replyToContent != null && message.replyToContent!.isNotEmpty && !isDeleted ? 4 : 10,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: isDeleted
                  ? cs.surfaceContainerHighest
                  : isMe
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF005C4B)
                          : const Color(0xFFDCF8C6))
                      : (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF202C33)
                          : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(8),
                topRight: const Radius.circular(8),
                bottomLeft: isMe ? const Radius.circular(8) : const Radius.circular(2),
                bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(8),
              ),
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Reply inner container
                if (message.replyToContent != null && message.replyToContent!.isNotEmpty && !isDeleted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFFB1D9A8)
                          : (Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF2A3942)
                              : const Color(0xFFF5F6F8)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF075E54)
                                : cs.primary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(2),
                              bottomLeft: Radius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(message.replyToSender ?? '',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isMe
                                          ? const Color(0xFF075E54)
                                          : cs.primary,
                                      fontWeight: FontWeight.w600)),
                              Text(message.replyToContent ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isMe
                                          ? const Color(0xFF1B3A2C)
                                          : cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                // Product link
                if (message.productName != null && message.productName!.isNotEmpty && !isDeleted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.tertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag, size: 14, color: cs.tertiary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(message.productName!,
                              style: TextStyle(fontSize: 12, color: cs.tertiary)),
                        ),
                      ],
                    ),
                  ),
                // Message content
                if (isDeleted)
                  Text(context.tr('message_deleted'),
                      style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant))
                else
                  Text(message.content,
                      style: TextStyle(
                        fontSize: 15,
                        color: isMe
                            ? (Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF111B21))
                            : cs.onSurface,
                      )),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEdited && !isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(context.tr('edited'),
                            style: TextStyle(
                                fontSize: 10, color: isMe ? cs.onPrimary.withValues(alpha: 0.7) : cs.onSurfaceVariant)),
                      ),
                    if (showTime)
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? cs.onPrimary.withValues(alpha: 0.7)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    if (isMe && !isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _StatusIcon(
                          isRead: message.isRead,
                          isDelivered: message.isDelivered,
                          color: cs.onPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
                // Reactions
                if (message.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: message.reactions.entries.map((e) {
                        return Container(
                          margin: const EdgeInsets.only(right: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                            '${e.key} ${e.value.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          // Actions (long press)
          if (!isDeleted)
            Padding(
              padding: EdgeInsets.only(top: 2, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onReply != null)
                    GestureDetector(
                      onTap: onReply,
                      child: Icon(Icons.reply, size: 14, color: cs.outline),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showReactions(context),
                    child: Icon(Icons.add_reaction, size: 14, color: cs.outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showReactions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((e) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  onReact(e);
                },
                child: Text(e, style: const TextStyle(fontSize: 32)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusIcon extends StatelessWidget {
  final bool isRead;
  final bool isDelivered;
  final Color color;

  const _StatusIcon({
    required this.isRead,
    required this.isDelivered,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (isRead) {
      return Icon(Icons.done_all, size: 14, color: Colors.lightBlue.shade300);
    }
    if (isDelivered) {
      return Icon(Icons.done_all, size: 14, color: color);
    }
    return Icon(Icons.done, size: 14, color: color);
  }
}
