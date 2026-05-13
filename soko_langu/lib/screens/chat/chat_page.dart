import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../call/video_call_screen.dart';
import '../profile/public_profile_screen.dart';
import '../../services/cloudinary_service.dart';
import '../../services/call_service.dart';
import '../../models/message_model.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';
import '../../widgets/verified_badge.dart';
import '../../main.dart';

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
  final UserService userService = UserService();
  final CallService _callService = CallService();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  UserProfile? _sellerProfile;
  bool _showSellerInfo = false;
  bool _isRecording = false;
  String? _playingVoiceMessageId;
  String? _editingMessageId;
  String? _activeCallId;
  bool _isCalling = false;
  bool _isTyping = false;
  String? _wallpaperPath;
  Timer? _typingDebounce;

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
    _audioPlayer.dispose();
    _typingDebounce?.cancel();
    chatService.stopTyping(widget.receiverId);
    super.dispose();
  }

  void _onTyping() {
    if (_messageController.text.trim().isEmpty) {
      _typingDebounce?.cancel();
      if (_isTyping) {
        _isTyping = false;
        chatService.stopTyping(widget.receiverId);
      }
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      chatService.startTyping(widget.receiverId);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        chatService.stopTyping(widget.receiverId);
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
          productName: widget.productName.isNotEmpty
              ? widget.productName
              : null,
        );
      }
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr('error')}: $e')));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final granted = await requestPermissionWithDialog(
        context,
        Permission.photos,
        'permission_photos',
      );
      if (!granted) return;
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final url = await CloudinaryService.uploadImage(
        image,
        folder: 'chat_images',
      );

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
    final granted = await requestPermissionWithDialog(
      context,
      Permission.microphone,
      'permission_microphone',
    );
    if (!granted) return;
    if (await _recorder.hasPermission()) {
      await _recorder.start(const RecordConfig(), path: _voiceMessagePath());
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;

    try {
      final url = await CloudinaryService.uploadFromPath(
        path,
        folder: 'voice_messages',
      );

      await chatService.sendMessage(
        receiverId: widget.receiverId,
        content: 'voice://$url',
        productId: widget.productName.isNotEmpty ? widget.receiverId : null,
        productName: widget.productName.isNotEmpty ? widget.productName : null,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr('voice')}: $e')));
      }
    }
  }

  String _voiceMessagePath() {
    final dir = Directory.systemTemp.path;
    return '$dir/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  }

  Future<void> _playVoiceMessage(String messageId, String url) async {
    if (_playingVoiceMessageId == messageId) {
      await _audioPlayer.stop();
      setState(() => _playingVoiceMessageId = null);
      return;
    }
    setState(() => _playingVoiceMessageId = messageId);
    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(url));
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoiceMessageId = null);
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _cancelEdit() {
    _editingMessageId = null;
    _messageController.clear();
    setState(() {});
  }

  Future<void> _deleteMessage(Message message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_message')),
        content: Text(context.tr('delete_message_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await chatService.deleteMessage(
          otherUserId: widget.receiverId,
          messageId: message.id,
        );
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.tr('delete_failed')}: $e')),
          );
        }
      }
    }
  }

  Future<void> _startVideoCall() async {
    try {
      final callId = await _callService.initiateCall(
        calleeId: widget.receiverId,
        type: 'video',
        callerName: FirebaseAuth.instance.currentUser?.displayName,
      );
      if (mounted)
        setState(() {
          _activeCallId = callId;
          _isCalling = true;
        });
      _listenForCallAnswer(callId, isVideo: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('call_failed')} $e")),
        );
      }
    }
  }

  Future<void> _startVoiceCall() async {
    try {
      final callId = await _callService.initiateCall(
        calleeId: widget.receiverId,
        type: 'voice',
        callerName: FirebaseAuth.instance.currentUser?.displayName,
      );
      if (mounted)
        setState(() {
          _activeCallId = callId;
          _isCalling = true;
        });
      _listenForCallAnswer(callId, isVideo: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('call_failed')} $e")),
        );
      }
    }
  }

  void _listenForCallAnswer(String callId, {required bool isVideo}) {
    _callService.myActiveCallStream().listen((call) {
      if (!mounted) return;
      if (call == null || call['id'] != callId) return;
      if (call['status'] == 'connected') {
        setState(() => _isCalling = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoCallScreen(
              channelName: call['channelName'] as String,
              isAudioOnly: !isVideo,
              callId: callId,
              remoteName: widget.receiverName,
              remoteImage: _sellerProfile?.profileImage,
            ),
          ),
        );
      } else if (call['status'] == 'declined' ||
          call['status'] == 'ended' ||
          call['status'] == 'cancelled') {
        setState(() {
          _activeCallId = null;
          _isCalling = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr('call_ended'))));
        }
      }
    });
  }

  Future<void> _cancelCall() async {
    if (_activeCallId != null) {
      await _callService.cancelCall(_activeCallId!);
      setState(() {
        _activeCallId = null;
        _isCalling = false;
      });
    }
  }

  Future<void> _pickWallpaper() async {
    final granted = await requestPermissionWithDialog(
      context,
      Permission.photos,
      'permission_photos',
    );
    if (!granted) return;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_wallpaper', image.path);
    if (mounted) setState(() => _wallpaperPath = image.path);
  }

  @override
  Widget build(BuildContext context) {
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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicProfileScreen(
                  userId: widget.receiverId,
                  userName: widget.receiverName,
                ),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.transparent,
                backgroundImage: _sellerProfile?.profileImage.isNotEmpty == true
                    ? NetworkImage(_sellerProfile!.profileImage)
                    : null,
                child: _sellerProfile?.profileImage.isEmpty != false
                    ? Text(
                        widget.receiverName.isNotEmpty
                            ? widget.receiverName[0].toUpperCase()
                            : widget.receiverId[0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFF2D6A4F)),
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
                          widget.receiverName.isNotEmpty
                              ? widget.receiverName
                              : widget.receiverId,
                          style: const TextStyle(
                            color: Color(0xFF2D6A4F),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        StreamBuilder<bool>(
                          stream: presenceService.isOnline(widget.receiverId),
                          builder: (context, snap) {
                            final online = snap.data ?? false;
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: online
                                    ? Colors.greenAccent
                                    : Colors.grey,
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
                        style: const TextStyle(
                          color: Color(0xFF40916C),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: Color(0xFF2D6A4F)),
            onPressed: _startVoiceCall,
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Color(0xFF2D6A4F)),
            onPressed: _startVideoCall,
          ),
          IconButton(
            icon: const Icon(Icons.wallpaper, color: Color(0xFF2D6A4F)),
            onPressed: _pickWallpaper,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF2D6A4F)),
            onPressed: () => setState(() => _showSellerInfo = !_showSellerInfo),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_wallpaperPath != null && File(_wallpaperPath!).existsSync())
            Positioned.fill(
              child: Image.file(File(_wallpaperPath!), fit: BoxFit.cover),
            ),
          if (_isCalling)
            _buildCallingBanner()
          else
            Column(
              children: [
                if (_showSellerInfo && _sellerProfile != null)
                  _buildSellerInfoBanner(),
                if (widget.productName.isNotEmpty) _buildProductReference(),
                Expanded(child: _buildMessagesList(user)),
                _buildTypingIndicator(),
                _buildInputArea(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(User? user) {
    return StreamBuilder<List<Message>>(
      stream: chatService.getMessages(widget.receiverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data ?? [];
        if (messages.isEmpty) {
          return _buildEmptyState();
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(10),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMe = message.senderId == user?.uid;
            return _buildMessageBubble(message, isMe);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: Color(0xFF40916C),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.tr('no_messages_yet'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D6A4F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('start_conversation'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerInfoBanner() {
    final s = _sellerProfile!;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white.withValues(alpha: 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(
                            userId: widget.receiverId,
                            userName: widget.receiverName,
                          ),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 30,
                      backgroundImage: s.profileImage.isNotEmpty
                          ? NetworkImage(s.profileImage)
                          : null,
                      child: s.profileImage.isEmpty
                          ? Text(
                              s.displayName.isNotEmpty
                                  ? s.displayName[0].toUpperCase()
                                  : widget.receiverId[0].toUpperCase(),
                              style: const TextStyle(color: Color(0xFF2D6A4F)),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                s.displayName.isNotEmpty
                                    ? s.displayName
                                    : widget.receiverName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF2D6A4F),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            VerifiedBadge(tier: s.accountTier, size: 14),
                          ],
                        ),
                        if (s.location.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                s.location,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (s.bio.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  s.bio,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
              if (s.phone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: Color(0xFF2D6A4F)),
                    const SizedBox(width: 4),
                    Text(
                      s.phone,
                      style: const TextStyle(
                        color: Color(0xFF2D6A4F),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
              if (s.paymentNumbers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  "${context.tr('payment_methods')}:",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF2D6A4F),
                  ),
                ),
                ...s.paymentNumbers.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "${e.key}: ${e.value}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2D6A4F),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductReference() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white.withValues(alpha: 0.9),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag, size: 16, color: Color(0xFF2D6A4F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.tr('replied_to')} ${widget.productName}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF2D6A4F)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<bool>(
      stream: chatService.typingStream(widget.receiverId),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox(height: 4);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF2D6A4F),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.receiverName.isNotEmpty ? widget.receiverName : ''}${context.tr('typing')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF2D6A4F),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: Colors.white.withValues(alpha: 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_editingMessageId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit,
                        size: 16,
                        color: Color(0xFF2D6A4F),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('editing_message'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2D6A4F),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _cancelEdit,
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image, color: Color(0xFF2D6A4F)),
                    onPressed: _editingMessageId != null
                        ? null
                        : _pickAndSendImage,
                  ),
                  GestureDetector(
                    onLongPressStart: _editingMessageId != null
                        ? null
                        : (_) => _startRecording(),
                    onLongPressEnd: _editingMessageId != null
                        ? null
                        : (_) => _stopAndSendRecording(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isRecording
                            ? Colors.red
                            : const Color(0xFF2D6A4F),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: context.tr('type_message'),
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: FloatingActionButton(
                      onPressed: _sendMessage,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      mini: true,
                      child: Icon(
                        _editingMessageId != null ? Icons.check : Icons.send,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    final isVoice = message.content.startsWith('voice://');
    final isImage =
        !isVoice &&
        (message.content.startsWith('http') &&
            (message.content.contains('.jpg') ||
                message.content.contains('.jpeg') ||
                message.content.contains('.png') ||
                message.content.contains('.gif')));
    final isDeleted = message.content == 'deleted';

    final bubble = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.all(isImage ? 4 : 12),
        constraints: BoxConstraints(
          maxWidth: isImage ? 250 : MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMe ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDeleted && isMe)
              Text(
                context.tr('message_deleted'),
                style: TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: Colors.white70,
                ),
              )
            else if (isDeleted)
              Text(
                context.tr('message_deleted'),
                style: TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[500],
                ),
              )
            else if (isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.content,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              )
            else if (isVoice)
              _buildVoiceBubble(message, isMe)
            else
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 16,
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMe ? Colors.white70 : Colors.grey[500],
                  ),
                ),
                if (message.isEdited && !isDeleted)
                  Text(
                    context.tr('edited'),
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isMe ? Colors.white60 : Colors.grey[400],
                    ),
                  ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isRead
                        ? const Color(0xFF8ECAE6)
                        : Colors.white60,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (!isMe) return bubble;

    return GestureDetector(
      onLongPress: () => _showMessageActions(message),
      child: bubble,
    );
  }

  void _showMessageActions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(context.tr('edit')),
              onTap: () {
                Navigator.pop(ctx);
                _editingMessageId = message.id;
                _messageController.text = message.content;
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                context.tr('delete'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMessage(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceBubble(Message message, bool isMe) {
    final url = message.content.replaceFirst('voice://', '');
    final isPlaying = _playingVoiceMessageId == message.id;
    return InkWell(
      onTap: () => _playVoiceMessage(message.id, url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPlaying ? Icons.stop : Icons.play_arrow,
            color: isMe ? Colors.white : const Color(0xFF2D6A4F),
          ),
          const SizedBox(width: 8),
          Container(
            width: 80,
            height: 4,
            decoration: BoxDecoration(
              color: isMe ? Colors.white30 : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: isPlaying ? 0.6 : 0.3,
              child: Container(
                decoration: BoxDecoration(
                  color: isMe ? Colors.white : const Color(0xFF2D6A4F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.tr('voice'),
            style: TextStyle(
              fontSize: 13,
              color: isMe ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallingBanner() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: Color(0xFF2D6A4F),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('calling'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D6A4F),
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: _cancelCall,
            icon: const Icon(Icons.call_end, color: Colors.red),
            label: const Text(
              'Cancel',
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
