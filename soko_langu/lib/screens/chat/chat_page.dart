import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../services/cloudinary_service.dart';
import '../../models/message_model.dart';
import 'package:soko_langu/services/chat_service.dart';
import 'package:soko_langu/services/chat_typing.dart';
import '../../services/user_service.dart';
import '../../services/presence_service.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/verified_badge.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String productName;

  const ChatPage({
    super.key,
    required this.receiverId,
    this.receiverName = '',
    this.productName = '',
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final ChatService chatService = ChatService();
  final ChatTyping chatTyping = ChatTyping();
  final UserService userService = UserService();
  final PresenceService _presenceService = PresenceService();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _playerCompleteSub;
  UserProfile? _sellerProfile;
  bool _showSellerInfo = false;
  bool _isRecording = false;
  String? _playingVoiceMessageId;
  String? _editingMessageId;
  bool _isTyping = false;
  String? _wallpaperPath;
  Timer? _typingDebounce;

  String? _replyToMessageId;
  String? _replyToContent;
  String? _replyToSender;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
    _loadWallpaper();
    chatService.markAsRead(widget.receiverId);
    _messageController.addListener(_onTyping);
  }

  Future<void> _loadWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _wallpaperPath = prefs.getString('chat_wallpaper'));
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _playerCompleteSub?.cancel();
    _audioPlayer.dispose();
    _typingDebounce?.cancel();
    chatTyping.sendTypingStatus(widget.receiverId, false);
    super.dispose();
  }

  void _onTyping() {
    if (_messageController.text.trim().isEmpty) {
      _typingDebounce?.cancel();
      if (_isTyping) {
        _isTyping = false;
        chatTyping.sendTypingStatus(widget.receiverId, false);
      }
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      chatTyping.sendTypingStatus(widget.receiverId, true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        chatTyping.sendTypingStatus(widget.receiverId, false);
      }
    });
  }

  Future<void> _loadSellerProfile() async {
    final profile = await userService.getProfile(widget.receiverId);
    if (mounted) setState(() => _sellerProfile = profile);
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    try {
      if (_editingMessageId != null) {
        await chatService.editMessage(
          otherUserId: widget.receiverId,
          messageId: _editingMessageId!,
          newContent: _messageController.text.trim(),
        );
        _editingMessageId = null;
      } else {
        await chatService.sendMessage(
          receiverId: widget.receiverId,
          content: _messageController.text.trim(),
          productId: widget.productName.isNotEmpty ? widget.receiverId : null,
          productName: widget.productName.isNotEmpty ? widget.productName : null,
          replyTo: _replyToMessageId,
          replyToContent: _replyToContent,
          replyToSender: _replyToSender,
        );
        _replyToMessageId = null;
        _replyToContent = null;
        _replyToSender = null;
      }
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('error')}: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final granted = await requestPermissionWithDialog(context, Permission.photos, 'permission_photos');
      if (!granted) return;
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final url = await CloudinaryService.uploadImage(image, folder: 'chat_images');

      await chatService.sendMessage(
        receiverId: widget.receiverId,
        content: url,
        productId: widget.productName.isNotEmpty ? widget.receiverId : null,
        productName: widget.productName.isNotEmpty ? widget.productName : null,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('send_photo')}: $e')),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    final granted = await requestPermissionWithDialog(context, Permission.microphone, 'permission_microphone');
    if (!granted) return;
    try {
      await _recorder.start(const RecordConfig(), path: _voiceMessagePath());
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Record start error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('voice')}: $e')),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path == null) return;

      final url = await CloudinaryService.uploadFromPath(path, folder: 'chat_voice');
      await chatService.sendMessage(
        receiverId: widget.receiverId,
        content: 'voice://$url',
        messageType: 'voice',
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('Record stop error: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  String _voiceMessagePath() {
    final dir = Directory.systemTemp;
    return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  Future<void> _playVoiceMessage(String messageId, String url) async {
    if (_playingVoiceMessageId == messageId) {
      await _audioPlayer.stop();
      setState(() => _playingVoiceMessageId = null);
      return;
    }
    if (_playingVoiceMessageId != null) await _audioPlayer.stop();

    _playerCompleteSub?.cancel();
    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      setState(() => _playingVoiceMessageId = null);
    });

    await _audioPlayer.play(UrlSource(url));
    setState(() => _playingVoiceMessageId = messageId);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _cancelEdit() {
    _editingMessageId = null;
    _messageController.clear();
    setState(() {});
  }

  Future<void> _pickWallpaper() async {
    final granted = await requestPermissionWithDialog(context, Permission.photos, 'permission_photos');
    if (!granted) return;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_wallpaper', image.path);
    if (mounted) setState(() => _wallpaperPath = image.path);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFD8F3DC), Color(0xFFF0F9F1)],
            ),
          ),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => context.push('${AppRoutes.publicProfile}/${widget.receiverId}', extra: widget.receiverName),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.transparent,
                backgroundImage: _sellerProfile?.profileImage.isNotEmpty == true
                    ? NetworkImage(_sellerProfile!.profileImage)
                    : null,
                child: _sellerProfile?.profileImage.isEmpty != false
                    ? Text(
                        widget.receiverName.isNotEmpty ? widget.receiverName[0].toUpperCase() : widget.receiverId[0].toUpperCase(),
                        style: TextStyle(color: cs.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.receiverName.isNotEmpty ? widget.receiverName : widget.receiverId,
                          style: TextStyle(color: cs.primary, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        StreamBuilder<bool>(
                          stream: _presenceService.isOnline(widget.receiverId),
                          builder: (context, snap) {
                            final online = snap.data ?? false;
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: online ? Colors.greenAccent : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (_sellerProfile?.location.isNotEmpty == true)
                      Text(
                        _sellerProfile!.location,
                        style: TextStyle(color: cs.primary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.wallpaper, color: cs.primary),
            onPressed: _pickWallpaper,
          ),
          IconButton(
            icon: Icon(Icons.info_outline, color: cs.primary),
            onPressed: () => setState(() => _showSellerInfo = !_showSellerInfo),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_wallpaperPath != null && File(_wallpaperPath!).existsSync())
            Positioned.fill(child: Image.file(File(_wallpaperPath!), fit: BoxFit.cover)),
          Column(
            children: [
              if (_showSellerInfo && _sellerProfile != null) _buildSellerInfoBanner(cs),
              if (widget.productName.isNotEmpty) _buildProductReference(cs),
              Expanded(child: _buildMessagesList(user, cs)),
              _buildTypingIndicator(cs),
              _buildInputArea(cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(User? user, ColorScheme cs) {
    return StreamBuilder<List<Message>>(
      stream: chatService.getMessages(widget.receiverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const GoogleLoadingPage();
        final messages = snapshot.data ?? [];
        if (messages.isEmpty) return _buildEmptyState(cs);
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(10),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMe = message.senderId == user?.uid;
            return _buildMessageBubble(message, isMe, cs);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: cs.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              context.tr('no_messages'),
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerInfoBanner(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sellerProfile!.displayName,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary),
          ),
          if (_sellerProfile!.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_sellerProfile!.bio, style: TextStyle(fontSize: 14, color: cs.onSurface)),
            ),
          if (_sellerProfile!.location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(_sellerProfile!.location, style: TextStyle(fontSize: 14, color: cs.onSurface)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductReference(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1)),
      child: Row(
        children: [
          Icon(Icons.shopping_bag, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.tr('chatting_about')}: ${widget.productName}',
              style: TextStyle(fontSize: 13, color: cs.primary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme cs) {
    return StreamBuilder<bool>(
      stream: chatTyping.observeTyping(widget.receiverId),
      builder: (context, snap) {
        final isTyping = snap.data ?? false;
        if (!isTyping) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '${widget.receiverName} ${context.tr('is_typing')}',
                style: TextStyle(fontSize: 13, color: cs.primary, fontStyle: FontStyle.italic),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editingMessageId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(context.tr('editing_message'), style: TextStyle(fontSize: 13, color: cs.primary)),
                  const Spacer(),
                  GestureDetector(onTap: _cancelEdit, child: Icon(Icons.close, size: 18, color: cs.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
          if (_replyToMessageId != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: cs.primary, width: 3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_replyToSender ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary)),
                        Text(_replyToContent ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() { _replyToMessageId = null; _replyToContent = null; _replyToSender = null; }),
                    child: Icon(Icons.close, size: 18, color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(icon: Icon(Icons.image, color: cs.primary), onPressed: _editingMessageId != null ? null : _pickAndSendImage),
              GestureDetector(
                onLongPressStart: _editingMessageId != null ? null : (_) => _startRecording(),
                onLongPressEnd: _editingMessageId != null ? null : (_) => _stopAndSendRecording(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _isRecording ? Colors.red : cs.primary, shape: BoxShape.circle),
                  child: Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(25), border: Border.all(color: cs.outlineVariant)),
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: context.tr('type_message'),
                      hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF40916C)]), shape: BoxShape.circle),
                child: FloatingActionButton(
                  onPressed: _sendMessage,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  mini: true,
                  child: Icon(_editingMessageId != null ? Icons.check : Icons.send, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe, ColorScheme cs) {
    final isVoice = message.content.startsWith('voice://');
    final isImage = !isVoice && (message.content.startsWith('http') && (message.content.contains('.jpg') || message.content.contains('.jpeg') || message.content.contains('.png') || message.content.contains('.gif')));
    final isDeleted = message.isDeletedForEveryone;
    final hasReply = message.replyToContent != null && message.replyToContent!.isNotEmpty;

    final bubble = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(message),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.all(isImage ? 4 : 12),
          constraints: BoxConstraints(maxWidth: isImage ? 250 : MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            gradient: isMe ? const LinearGradient(colors: [Color(0xFF2D6A4F), Color(0xFF40916C)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            color: isMe ? null : cs.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasReply) _buildReplyPreview(message, isMe, cs),
              if (isDeleted)
                Text(context.tr('deleted_for_everyone'), style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: isMe ? Colors.white70 : cs.onSurface.withValues(alpha: 0.6)))
              else if (isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: message.content, fit: BoxFit.cover, width: double.infinity, placeholder: (context, url) => Container(height: 200, color: cs.surfaceContainerHighest, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))),
                )
              else if (isVoice)
                _buildVoiceBubble(message, isMe, cs)
              else
                Text(message.content, style: TextStyle(fontSize: 16, color: isMe ? Colors.white : cs.onSurface)),
              if (message.reactions.isNotEmpty) _buildReactions(message, isMe),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : cs.onSurface.withValues(alpha: 0.6))),
                  if (message.isEdited && !isDeleted) Text(context.tr('edited'), style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isMe ? Colors.white60 : cs.onSurface.withValues(alpha: 0.4))),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isRead ? Icons.done_all : message.isDelivered ? Icons.done_all : Icons.done,
                      size: 14,
                      color: message.isRead ? const Color(0xFF8ECAE6) : message.isDelivered ? (isMe ? Colors.white38 : cs.onSurface.withValues(alpha: 0.4)) : Colors.white60,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return bubble;
  }

  Widget _buildReplyPreview(Message message, bool isMe, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withValues(alpha: 0.15) : cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: isMe ? Colors.white.withValues(alpha: 0.4) : cs.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.replyToSender ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isMe ? Colors.white.withValues(alpha: 0.8) : cs.primary)),
          const SizedBox(height: 2),
          Text(message.replyToContent!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : cs.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildReactions(Message message, bool isMe) {
    final reactions = message.reactions;
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: reactions.entries.map((entry) {
          return GestureDetector(
            onTap: () => chatService.addReaction(otherUserId: widget.receiverId, messageId: message.id, emoji: entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: isMe ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Text(entry.key, style: const TextStyle(fontSize: 14)), if (entry.value.length > 1) Text('${entry.value.length}', style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54))]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoiceBubble(Message message, bool isMe, ColorScheme cs) {
    final url = message.content.replaceFirst('voice://', '');
    final isPlaying = _playingVoiceMessageId == message.id;
    return InkWell(
      onTap: () => _playVoiceMessage(message.id, url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPlaying ? Icons.stop : Icons.play_arrow, color: isMe ? Colors.white : cs.primary),
          const SizedBox(width: 8),
          Container(width: 80, height: 4, decoration: BoxDecoration(color: isMe ? Colors.white30 : cs.outlineVariant, borderRadius: BorderRadius.circular(2)), child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: isPlaying ? 0.6 : 0.3, child: Container(decoration: BoxDecoration(color: isMe ? Colors.white : cs.primary, borderRadius: BorderRadius.circular(2))))),
          const SizedBox(width: 8),
          Text(context.tr('voice'), style: TextStyle(fontSize: 13, color: isMe ? Colors.white70 : cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  void _showMessageActions(Message message) {
    final isMe = message.senderId == FirebaseAuth.instance.currentUser?.uid;
    final canDeleteForEveryone = isMe && DateTime.now().difference(message.timestamp).inMinutes <= 15;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.reply), title: Text(context.tr('reply')), onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _replyToMessageId = message.id;
                _replyToContent = message.content.length > 50 ? '${message.content.substring(0, 50)}...' : message.content;
                _replyToSender = isMe ? context.tr('you') : widget.receiverName;
              });
            }),
            ListTile(leading: const Icon(Icons.forward), title: Text(context.tr('forward')), onTap: () {
              Navigator.pop(ctx);
              _forwardMessage(message);
            }),
            ListTile(leading: const Icon(Icons.emoji_emotions_outlined), title: Text(context.tr('react')), onTap: () {
              Navigator.pop(ctx);
              _showReactionPicker(message);
            }),
            if (isMe) ListTile(leading: const Icon(Icons.edit), title: Text(context.tr('edit')), onTap: () {
              Navigator.pop(ctx);
              _editingMessageId = message.id;
              _messageController.text = message.content;
              setState(() {});
            }),
            if (canDeleteForEveryone) ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: Text(context.tr('delete_for_everyone'), style: const TextStyle(color: Colors.red)), onTap: () {
              Navigator.pop(ctx);
              _deleteMessageForEveryone(message);
            }),
            ListTile(leading: Icon(isMe ? Icons.delete : Icons.delete_outline, color: Colors.red), title: Text(isMe ? context.tr('delete_for_me') : context.tr('delete'), style: const TextStyle(color: Colors.red)), onTap: () {
              Navigator.pop(ctx);
              _deleteMessage(message);
            }),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(Message message) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis.map((emoji) => GestureDetector(onTap: () { Navigator.pop(ctx); chatService.addReaction(otherUserId: widget.receiverId, messageId: message.id, emoji: emoji); }, child: Text(emoji, style: const TextStyle(fontSize: 32)))).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _forwardMessage(Message message) async {
    try {
      final users = await FirebaseFirestore.instance.collection('users').orderBy('displayName').limit(50).get();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: users.docs.where((u) => u.id != FirebaseAuth.instance.currentUser?.uid).map((u) {
              return ListTile(
                leading: CircleAvatar(child: Text((u.data()['displayName'] ?? '?')[0])),
                title: Text(u.data()['displayName'] ?? 'Unknown'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await chatService.forwardMessage(messageId: message.id, fromUserId: widget.receiverId, toUserId: u.id);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('message_forwarded'))));
                },
              );
            }).toList(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.tr('error')}: $e')));
    }
  }

  Future<void> _deleteMessageForEveryone(Message message) async {
    try {
      await chatService.deleteMessageForEveryone(otherUserId: widget.receiverId, messageId: message.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('deleted_for_everyone'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      await chatService.deleteMessageForMe(otherUserId: widget.receiverId, messageId: message.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
