import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/agora_config.dart';
import '../../services/live_stream_service.dart';
import '../../utils/helpers.dart';

class GoLiveScreen extends StatefulWidget {
  final String productId;
  final String productName;
  final String? productImage;

  const GoLiveScreen({
    super.key,
    required this.productId,
    required this.productName,
    this.productImage,
  });

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen> {
  RtcEngine? _engine;
  bool _isLive = false;
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _streamEnded = false;
  String? _channelName;
  final _chatScroll = ScrollController();
  int _reactionCount = 0;

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  @override
  void dispose() {
    _engine?.release();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _initAgora() async {
    final camGranted = await requestPermissionWithDialog(
      context,
      Permission.camera,
      'permission_camera',
    );
    if (!camGranted || !mounted) return;

    final micGranted = await requestPermissionWithDialog(
      context,
      Permission.microphone,
      'permission_microphone',
    );
    if (!micGranted) return;

    _engine = createAgoraRtcEngine();
    await _engine?.initialize(RtcEngineContext(appId: agoraAppId));
    await _engine?.enableVideo();
    await _engine?.startPreview();

    _engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() => _isLive = true);
        },
      ),
    );
  }

  Future<void> _startLive() async {
    if (_engine == null) return;

    try {
      final channelName = await LiveStreamService().startLive(
        productId: widget.productId,
        productName: widget.productName,
        productImage: widget.productImage,
      );
      _channelName = channelName;

      final token = await getAgoraToken(
        channelName: channelName,
        role: 'broadcaster',
      );
      await _engine?.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
        ),
      );

      _listenReactions(channelName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start live: $e')));
    }
  }

  void _listenReactions(String channelName) {
    FirebaseFirestore.instance
        .collection('live_streams')
        .doc(channelName)
        .collection('reactions')
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _reactionCount = snap.docs.length);
        });
  }

  Future<void> _endLive() async {
    setState(() => _streamEnded = true);
    if (_channelName != null) {
      await LiveStreamService().endLive(_channelName!);
    }
    await _engine?.leaveChannel();
  }

  void _shareStream() {
    if (_channelName == null) return;
    Share.share('Watch my live stream on Soko Langu! ${widget.productName}');
  }

  @override
  Widget build(BuildContext context) {
    if (_streamEnded) return _buildEndedScreen();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('End Live?'),
            content: const Text(
              'Are you sure you want to end this live stream?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('End', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await _endLive();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (_engine != null)
                      AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _engine!,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    // Top bar
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: _buildTopBar(),
                    ),
                    // Bottom product info
                    if (_isLive)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: _buildProductBar(),
                      ),
                  ],
                ),
              ),
              if (_isLive) _buildChatSection(),
              if (!_isLive) _buildPreLiveControls(),
            ],
          ),
        ),
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
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
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
                'Your live stream for ${widget.productName} has ended.\nTotal reactions: $_reactionCount',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go to Dashboard'),
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

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isLive ? Colors.red : Colors.grey[700],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLive)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                _isLive ? 'LIVE' : 'Preview',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (_isLive) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 14),
                const SizedBox(width: 4),
                Text(
                  '$_reactionCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white, size: 22),
          onPressed: _shareStream,
        ),
      ],
    );
  }

  Widget _buildProductBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (widget.productImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.productImage!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.image, color: Colors.white54, size: 20),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.productName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreLiveControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ctrlBtn(Icons.mic, _isMuted ? 'Unmute' : 'Mute', () async {
                await _engine?.muteLocalAudioStream(!_isMuted);
                setState(() => _isMuted = !_isMuted);
              }),
              _ctrlBtn(
                _isCameraOn ? Icons.videocam : Icons.videocam_off,
                _isCameraOn ? 'Camera' : 'Off',
                () async {
                  await _engine?.muteLocalVideoStream(_isCameraOn);
                  setState(() => _isCameraOn = !_isCameraOn);
                },
              ),
              _ctrlBtn(
                Icons.switch_camera,
                'Switch',
                () => _engine?.switchCamera(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _startLive,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text(
                'Go Live Now',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection() {
    return Container(
      height: 200,
      color: Colors.black87,
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('live_streams')
                  .doc(_channelName)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                final msgs = snap.data?.docs ?? [];
                return ListView.builder(
                  controller: _chatScroll,
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final data = msgs[i].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${data['sender'] ?? 'Viewer'}: ',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            TextSpan(
                              text: '${data['text']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(top: BorderSide(color: Colors.grey[800]!)),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Chat with viewers...',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
