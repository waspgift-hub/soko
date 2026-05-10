import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/agora_config.dart';
import '../../services/live_stream_service.dart';
import '../../models/product_model.dart';
import '../../utils/helpers.dart';
import '../home/product_detail.dart';
import '../../widgets/ad_banner.dart';
import 'gift_shop_dialog.dart';

class LiveScreen extends StatefulWidget {
  final LiveStream stream;

  const LiveScreen({super.key, required this.stream});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  RtcEngine? _engine;
  bool _isJoined = false;
  bool _streamEnded = false;
  final _chatController = TextEditingController();
  final _chatFocus = FocusNode();
  final List<_FloatingHeart> _hearts = [];
  bool _showInput = false;

  @override
  void initState() {
    super.initState();
    _joinLive();
    _checkStreamStatus();
  }

  @override
  void dispose() {
    _engine?.leaveChannel();
    _engine?.release();
    _chatController.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  Future<void> _checkStreamStatus() async {
    FirebaseFirestore.instance
        .collection('live_streams')
        .doc(widget.stream.channelName)
        .snapshots()
        .listen((snap) {
          if (snap.exists && snap.data()?['isActive'] == false && mounted) {
            setState(() => _streamEnded = true);
          }
        });
  }

  Future<void> _joinLive() async {
    final micGranted = await requestPermissionWithDialog(
      context,
      Permission.microphone,
      'permission_microphone',
    );
    if (!micGranted && mounted) return;

    _engine = createAgoraRtcEngine();
    await _engine?.initialize(RtcEngineContext(appId: agoraAppId));
    await _engine?.enableVideo();

    _engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() => _isJoined = true);
        },
      ),
    );

    final token = await getAgoraToken(
      channelName: widget.stream.channelName,
      role: 'audience',
    );
    await _engine?.joinChannel(
      token: token,
      channelId: widget.stream.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: ClientRoleType.clientRoleAudience,
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    setState(() => _showInput = false);
    _chatFocus.unfocus();

    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? user?.email ?? 'Viewer';

    await FirebaseFirestore.instance
        .collection('live_streams')
        .doc(widget.stream.channelName)
        .collection('messages')
        .add({
          'text': text,
          'sender': name,
          'senderId': user?.uid ?? '',
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _sendHeart() async {
    final rng = Random();
    final heart = _FloatingHeart(
      id: DateTime.now().millisecondsSinceEpoch,
      left: rng.nextDouble() * 0.7 + 0.1,
      delay: Duration(milliseconds: rng.nextInt(500)),
    );
    setState(() => _hearts.add(heart));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hearts.remove(heart));
    });

    await FirebaseFirestore.instance
        .collection('live_streams')
        .doc(widget.stream.channelName)
        .collection('reactions')
        .add({'type': 'heart', 'timestamp': FieldValue.serverTimestamp()});
  }

  void _shareStream() {
    Share.share(
      'Watch live now: ${widget.stream.productName} - ${widget.stream.userName} is live on Soko Langu!',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_streamEnded) return _buildEndedScreen();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Full-screen video
            if (_engine != null && _isJoined)
              AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: const VideoCanvas(uid: 1),
                  connection: RtcConnection(
                    channelId: widget.stream.channelName,
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Top bar
            Positioned(top: 8, left: 8, child: _buildTopBar()),

            // Gift notifications
            _buildGiftNotifications(),

            // Floating hearts
            ..._hearts.map((h) => _buildFloatingHeart(h)),

            // TikTok-style floating comments
            Positioned(
              bottom: 100,
              left: 8,
              right: 80,
              child: _buildTikTokComments(),
            ),

            // Banner ad
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: const AdBanner(showAlways: true),
            ),

            // Bottom overlay bar
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),

            // Streamer info
            Positioned(top: 60, right: 12, child: _buildStreamInfo()),

            // Input overlay when typing
            if (_showInput) _buildInputOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 4),
        const _LiveIndicator(),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white, size: 22),
          onPressed: _shareStream,
        ),
      ],
    );
  }

  Widget _buildStreamInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.grey,
            child: Text(
              widget.stream.userName.isNotEmpty
                  ? widget.stream.userName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.stream.userName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(
                    product: Product(
                      id: widget.stream.productId,
                      name: widget.stream.productName,
                      images: widget.stream.productImage != null
                          ? [widget.stream.productImage!]
                          : [],
                      price: 0,
                      description: '',
                      category: '',
                      subcategory: '',
                      location: '',
                      sellerId: widget.stream.userId,
                      sellerName: widget.stream.userName,
                      createdAt: DateTime.now(),
                      stock: 0,
                    ),
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Shop',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTikTokComments() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('live_streams')
          .doc(widget.stream.channelName)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: docs.reversed.take(3).map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final sender = data['sender'] ?? 'Viewer';
            final text = data['text'] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$sender ',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      TextSpan(
                        text: text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showInput = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Send a message...',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.favorite, color: Colors.red, size: 26),
            onPressed: _sendHeart,
          ),
          IconButton(
            icon: const Icon(
              Icons.card_giftcard,
              color: Colors.amber,
              size: 26,
            ),
            onPressed: _openGiftShop,
          ),
        ],
      ),
    );
  }

  Widget _buildInputOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: TextField(
                  controller: _chatController,
                  focusNode: _chatFocus,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Type message...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() => _showInput = false);
                _chatFocus.unfocus();
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close, color: Colors.white54, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftNotifications() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('live_gifts')
          .where('streamId', isEqualTo: widget.stream.channelName)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (ctx, snap) {
        final gifts = snap.data?.docs ?? [];
        if (gifts.isEmpty) return const SizedBox.shrink();
        final latest = gifts.first.data() as Map<String, dynamic>;
        return Positioned(
          top: 60,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${latest['giftEmoji'] ?? '🎁'}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  '${latest['fromName'] ?? 'Someone'} sent ${latest['giftName'] ?? 'a gift'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openGiftShop() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GiftShopDialog(
        streamerId: widget.stream.userId,
        streamId: widget.stream.channelName,
      ),
    );
  }

  Widget _buildEndedScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_tethering_off, size: 80, color: Colors.grey[600]),
              const SizedBox(height: 20),
              const Text(
                'Stream Ended',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.stream.userName}\'s live stream has ended.',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingHeart(_FloatingHeart heart) {
    return Positioned(
      left: MediaQuery.of(context).size.width * heart.left,
      bottom: 80 + (heart.id % 3) * 40.0,
      child: const Icon(Icons.favorite, color: Colors.red, size: 36),
    );
  }
}

class _FloatingHeart {
  final int id;
  final double left;
  final Duration delay;
  _FloatingHeart({required this.id, required this.left, required this.delay});
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
