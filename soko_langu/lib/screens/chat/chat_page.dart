import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../call/video_call_screen.dart';
import '../profile/public_profile_screen.dart';
import '../../services/cloudinary_service.dart';
import '../../models/message_model.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';
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
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  UserProfile? _sellerProfile;
  bool _showSellerInfo = false;
  bool _isRecording = false;
  String? _playingVoiceMessageId;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSellerProfile() async {
    final profile = await userService.getProfile(widget.receiverId);
    if (mounted) setState(() => _sellerProfile = profile);
  }

  // ========================
  // SEND TEXT MESSAGE
  // ========================
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    try {
      await chatService.sendMessage(
        receiverId: widget.receiverId,
        content: _messageController.text.trim(),
        productId: widget.productName.isNotEmpty ? widget.receiverId : null,
        productName: widget.productName.isNotEmpty ? widget.productName : null,
      );
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

  // ========================
  // SEND IMAGE
  // ========================
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

  // ========================
  // VOICE MESSAGE
  // ========================
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

      // Store as voice:// prefix so we know it's a voice message
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

  // ========================
  // CALLS
  // ========================
  void _startVideoCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(channelName: _callChannelName()),
      ),
    );
  }

  void _startVoiceCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoCallScreen(channelName: _callChannelName(), isAudioOnly: true),
      ),
    );
  }

  String _callChannelName() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ids = [uid, widget.receiverId]..sort();
    return 'call_${ids.join("_")}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green,
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
                        style: const TextStyle(color: Colors.green),
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
                            color: Colors.white,
                            fontSize: 16,
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
                          color: Colors.white70,
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
            icon: const Icon(Icons.phone, color: Colors.white),
            onPressed: _startVoiceCall,
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: _startVideoCall,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => setState(() => _showSellerInfo = !_showSellerInfo),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSellerInfo && _sellerProfile != null)
            _buildSellerInfoBanner(),
          if (widget.productName.isNotEmpty) _buildProductReference(),
          Expanded(child: _buildMessagesList(user)),
          _buildInputArea(),
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

  Widget _buildSellerInfoBanner() {
    final s = _sellerProfile!;
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.green[50],
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
                          style: const TextStyle(color: Colors.green),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.displayName.isNotEmpty
                          ? s.displayName
                          : widget.receiverName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (s.location.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.location,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
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
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
          if (s.phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  s.phone,
                  style: const TextStyle(color: Colors.green, fontSize: 13),
                ),
              ],
            ),
          ],
          if (s.paymentNumbers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "${context.tr('payment_methods')}:",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            ...s.paymentNumbers.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  "${e.key}: ${e.value}",
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductReference() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[100],
      child: Row(
        children: [
          const Icon(Icons.shopping_bag, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.tr('replied_to')} ${widget.productName}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          // Image
          IconButton(
            icon: const Icon(Icons.image, color: Colors.green),
            onPressed: _pickAndSendImage,
          ),
          // Voice
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopAndSendRecording(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red : Colors.green,
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
          // Text field
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: context.tr('type_message'),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: _sendMessage,
            backgroundColor: Colors.green,
            mini: true,
            child: const Icon(Icons.send, color: Colors.white),
          ),
        ],
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

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.all(isImage ? 4 : 12),
        constraints: BoxConstraints(
          maxWidth: isImage ? 250 : MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.green[100] : Colors.grey[100],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isImage)
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
              Text(message.content, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
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
            color: isMe ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 8),
          Container(
            width: 80,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: isPlaying ? 0.6 : 0.3,
              child: Container(
                decoration: BoxDecoration(
                  color: isMe ? Colors.green : Colors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(context.tr('voice'), style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
