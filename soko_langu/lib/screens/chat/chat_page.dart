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

  // Optimistic messages: tempId → Message
  final Map<String, Message> _optimisticMsgs = {};
  final Set<String> _confirmedSends = {};
  final Set<String> _failedSends = {};
  final Map<String, String> _tempToRealId = {};

  // Presence
  DateTime? _otherLastActive;
  Timer? _presenceTimer;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _roomId => _chatService.roomIdFor(_uid, widget.receiverId);

  StreamSubscription<bool>? _typingSub;
  StreamSubscription<DateTime?>? _presenceSub;

  @override
  void initState() {
    super.initState();
    _chatService.markAsRead(_roomId);
    _chatService.markMessagesAsRead(_roomId);
    _inputCtrl.addListener(_onInputChanged);
    _fetchReceiverPhone();
    _typingSub = _chatTyping.observeTyping(widget.receiverId).listen((t) {
      if (mounted) setState(() => _otherTyping = t);
    });
    _presenceSub = _userService.streamLastActive(widget.receiverId).listen((t) {
      if (mounted) setState(() => _otherLastActive = t);
    });
    _userService.updateLastActive();
    // Refresh presence every 30s while chat is open
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _userService.updateLastActive();
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
    _presenceSub?.cancel();
    _presenceTimer?.cancel();
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

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      senderId: _uid,
      receiverId: widget.receiverId,
      content: text,
      timestamp: DateTime.now(),
      isRead: false,
      isDelivered: false,
      productId: widget.productId,
      productName: widget.productName,
      replyTo: _replyTo,
      replyToContent: _replyToContent,
      replyToSender: _replyToSender,
    );
    _optimisticMsgs[tempId] = optimistic;

    _inputCtrl.clear();
    final replyToId = _replyTo;
    final replyToContent = _replyToContent;
    final replyToSender = _replyToSender;
    _replyTo = null;
    _replyToContent = null;
    _replyToSender = null;
    setState(() {});
    _scrollToBottom();

    // Fire HTTP send in background
    _chatService.sendMessage(
      receiverId: widget.receiverId,
      content: text,
      productId: widget.productId,
      productName: widget.productName,
      replyTo: replyToId,
      replyToContent: replyToContent,
      replyToSender: replyToSender,
    ).then((realId) {
      if (!mounted) return;
      if (realId != null && realId.isNotEmpty) {
        setState(() {
          _confirmedSends.add(tempId);
          _tempToRealId[tempId] = realId;
          _optimisticMsgs[tempId] = optimistic.copyWith(
            isDelivered: true,
          );
        });
      } else {
        setState(() => _failedSends.add(tempId));
      }
    });
  }

  void _retryMessage(Message failedMsg) {
    final text = failedMsg.content;
    if (text.isEmpty) return;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      senderId: _uid,
      receiverId: widget.receiverId,
      content: text,
      timestamp: DateTime.now(),
      isRead: false,
      isDelivered: false,
      productId: failedMsg.productId,
      productName: failedMsg.productName,
      replyTo: failedMsg.replyTo,
      replyToContent: failedMsg.replyToContent,
      replyToSender: failedMsg.replyToSender,
    );

    setState(() {
      _failedSends.remove(failedMsg.id);
      _optimisticMsgs.remove(failedMsg.id);
      _optimisticMsgs[tempId] = optimistic;
    });

    _chatService.sendMessage(
      receiverId: widget.receiverId,
      content: text,
      productId: failedMsg.productId,
      productName: failedMsg.productName,
      replyTo: failedMsg.replyTo,
      replyToContent: failedMsg.replyToContent,
      replyToSender: failedMsg.replyToSender,
    ).then((realId) {
      if (!mounted) return;
      if (realId != null && realId.isNotEmpty) {
        setState(() {
          _confirmedSends.add(tempId);
          _tempToRealId[tempId] = realId;
          _optimisticMsgs[tempId] = optimistic.copyWith(isDelivered: true);
        });
      } else {
        setState(() => _failedSends.add(tempId));
      }
    });
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

  /// Remove optimistic messages that are now confirmed by Firestore.
  void _removeConfirmedOptimistics() {
    _optimisticMsgs.removeWhere((tempId, msg) {
      if (!_confirmedSends.contains(tempId)) return false;
      final realId = _tempToRealId[tempId];
      if (realId != null) {
        if (_messages.any((m) => m.id == realId)) return true;
      }
      final matched = _messages.any((m) =>
          m.senderId == _uid &&
          m.content == msg.content &&
          (m.timestamp.difference(msg.timestamp).inSeconds.abs() < 60));
      if (matched) return true;
      return false;
    });
    _failedSends.removeWhere((id) {
      final msg = _optimisticMsgs[id];
      return msg != null &&
          DateTime.now().difference(msg.timestamp).inSeconds > 60;
    });
  }

  /// Merge Firestore messages with optimistic messages, sorted by timestamp.
  List<Message> _mergedMessages() {
    if (_optimisticMsgs.isEmpty) return _messages;
    final all = <Message>[..._messages, ..._optimisticMsgs.values];
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return all;
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
                    Row(
                      children: [
                        if (_otherTyping)
                          _TypingDots(color: cs.primary)
                        else if (UserService.isOnline(_otherLastActive))
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(context.tr('online'),
                                  style: TextStyle(fontSize: 12, color: const Color(0xFF25D366))),
                            ],
                          ),
                      ],
                    ),
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
                final msgs = snap.data ?? [];
                if (msgs != _messages) {
                  _messages = msgs;
                  // Remove optimistic messages that have been confirmed by Firestore
                  _removeConfirmedOptimistics();
                  if (!_autoScrolling) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollCtrl.hasClients) {
                        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                      }
                    });
                  }
                }
                final merged = _mergedMessages();
                // Mark incoming messages as read
                if (msgs.any((m) => m.senderId != _uid && !m.isRead)) {
                  _chatService.markMessagesAsRead(_roomId);
                }
                if (merged.isEmpty) {
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: merged.length,
                    itemBuilder: (_, i) {
                      final msg = merged[i];
                      final isFirstOfDay = i == 0 ||
                          !_isSameDay(msg.timestamp, merged[i - 1].timestamp);
                      final showTime = i == 0 ||
                          merged[i - 1].senderId != msg.senderId ||
                          merged[i - 1].timestamp.difference(msg.timestamp).abs() >
                              const Duration(minutes: 5);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isFirstOfDay) _dateSeparator(msg.timestamp, cs),
                          _MessageBubble(
                            message: msg,
                            isMe: msg.senderId == _uid,
                            showTime: showTime,
                            isFailed: _failedSends.contains(msg.id),
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
                            onRetry: _failedSends.contains(msg.id)
                                ? () => _retryMessage(msg)
                                : null,
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
          // Input bar (AI style)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.05))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  _buildMicButton(cs),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      maxLines: 5,
                      minLines: 1,
                      onSubmitted: (_) => _sendMessage(),
                      style: TextStyle(color: cs.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: context.tr('type_message'),
                        hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.05)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                        ),
                        filled: true,
                        fillColor: cs.onSurface.withValues(alpha: 0.04),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send_rounded, color: cs.onPrimary, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
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

  Widget _buildMicButton(ColorScheme cs) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Coming soon')),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.onSurface.withValues(alpha: 0.06),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.05),
          ),
        ),
        child: Icon(Icons.mic_none_rounded, color: cs.onSurface.withValues(alpha: 0.6), size: 20),
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
  final bool isFailed;
  final VoidCallback? onReply;
  final VoidCallback? onRetry;
  final void Function(String emoji) onReact;
  final ColorScheme cs;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showTime,
    this.isFailed = false,
    this.onReply,
    this.onRetry,
    required this.onReact,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final isDeleted = message.content == 'deleted' || message.isDeletedForEveryone;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe right → reply (trigger onReply)
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          onReply?.call();
        }
      },
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
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
                        child: isFailed
                            ? GestureDetector(
                                onTap: onRetry,
                                child: Icon(Icons.error_outline,
                                    size: 16, color: Colors.red.shade400),
                              )
                            : _StatusIcon(
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
        ),
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

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final bounce = (t < 0.5)
                ? 2 * t
                : 2 * (1 - t);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.translate(
                offset: Offset(0, -bounce * 3),
                child: Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.4 + bounce * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
