import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/agora_service.dart';
import '../../services/agora_config.dart';
import '../../services/live_stream_service.dart';
import '../../utils/helpers.dart';
import '../../extensions/context_tr.dart';

import 'package:cached_network_image/cached_network_image.dart';

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
  final AgoraService _agoraService = AgoraService();
  final LiveStreamService _liveService = LiveStreamService();
  bool _isLive = false;
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _streamEnded = false;
  bool _isStarting = false;
  bool _engineReady = false;
  String? _channelName;
  String? _prefetchedToken;
  final _chatScroll = ScrollController();
  int _reactionCount = 0;
  StreamSubscription? _reactionsSub;
  StreamSubscription? _coHostReqSub;
  List<Map<String, dynamic>> _coHostRequests = [];

  @override
  void initState() {
    super.initState();
    _channelName =
        'live_${FirebaseAuth.instance.currentUser?.uid}_${DateTime.now().millisecondsSinceEpoch}';
    _initAgora();
    _prefetchTokenAndDoc();
  }

  Future<void> _prefetchTokenAndDoc() async {
    try {
      _prefetchedToken = await getAgoraToken(
        channelName: _channelName!,
        role: 'broadcaster',
      );
    } catch (_) {}
    try {
      await LiveStreamService().startLive(
        productId: widget.productId,
        productName: widget.productName,
        productImage: widget.productImage,
        channelName: _channelName!,
        isActive: false,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _reactionsSub?.cancel();
    _coHostReqSub?.cancel();
    _agoraService.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _initAgora() async {
    try {
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
      if (!micGranted || !mounted) return;

      await _agoraService.initialize(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      );
      await _agoraService.engine.enableVideo();
      await _agoraService.engine.startPreview();

      _agoraService.engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            setState(() => _isLive = true);
          },
          onTokenPrivilegeWillExpire: (RtcConnection connection, String token) async {
            final newToken = await getAgoraToken(
              channelName: _channelName!,
              role: 'broadcaster',
            );
            if (newToken.isNotEmpty) {
              _agoraService.engine.renewToken(newToken);
            }
          },
        ),
      );
      if (mounted) setState(() => _engineReady = true);
    } catch (e) {
      debugPrint('initAgora error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('call_error')} $e")),
        );
      }
    }
  }

  Future<void> _startLive() async {
    if (!_engineReady) {
      await _initAgora();
      if (!_engineReady || !mounted) return;
    }
    setState(() => _isStarting = true);

    try {
      final channelName = _channelName!;
      String token = _prefetchedToken ?? '';
      if (token.isEmpty) {
        token = await getAgoraToken(
          channelName: channelName,
          role: 'broadcaster',
        );
      }
      await _agoraService.engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await Future.wait([
        LiveStreamService().activateLive(channelName),
        _agoraService.engine.joinChannel(
          token: token,
          channelId: channelName,
          uid: 0,
          options: const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            publishCameraTrack: true,
            publishMicrophoneTrack: true,
          ),
        ),
      ]);
      _listenReactions(channelName);
      _listenCoHostRequests(channelName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${context.tr('failed_start_live')} $e")),
      );
    }
  }

  void _listenReactions(String channelName) {
    _reactionsSub?.cancel();
    _reactionsSub = FirebaseFirestore.instance
        .collection('live_streams')
        .doc(channelName)
        .collection('reactions')
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _reactionCount = snap.docs.length);
        });
  }

  void _listenCoHostRequests(String channelName) {
    _coHostReqSub?.cancel();
    _coHostReqSub = _liveService.streamCoHostRequests(channelName).listen((requests) {
      if (mounted) {
        setState(() => _coHostRequests = requests);
        if (requests.isNotEmpty) {
          _showCoHostRequestDialog(requests.first);
        }
      }
    });
  }

  void _showCoHostRequestDialog(Map<String, dynamic> request) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('cohost_request')),
        content: Text("${request['viewerName'] ?? 'Someone'} ${context.tr('wants_to_cohost')}"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _declineCoHost(request['id'] as String);
            },
            child: Text(context.tr('decline')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _acceptCoHost(request['id'] as String, request['viewerId'] as String);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D6A4F)),
            child: Text(context.tr('accept'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptCoHost(String requestId, String viewerId) async {
    if (_channelName == null) return;
    try {
      await _liveService.acceptCoHost(_channelName!, requestId, viewerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('cohost_accepted')),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _declineCoHost(String requestId) async {
    if (_channelName == null) return;
    try {
      await _liveService.declineCoHost(_channelName!, requestId);
      if (mounted) {
        setState(() => _coHostRequests.removeWhere((r) => r['id'] == requestId));
      }
    } catch (e) {
      debugPrint('declineCoHost error: $e');
    }
  }

  Future<void> _endLive() async {
    setState(() => _streamEnded = true);
    _reactionsSub?.cancel();
    if (_channelName != null) {
      await LiveStreamService().endLive(_channelName!);
    }
    _agoraService.dispose();
  }

  void _shareStream() {
    if (_channelName == null) return;
    SharePlus.instance.share(
      ShareParams(text: "${context.tr('share_live')} ${widget.productName}"),
    );
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
            title: Text(context.tr('end_live')),
            content: const Text(
              'Are you sure you want to end this live stream?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(
                  context.tr('end_call'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await _endLive();
          if (!context.mounted) return;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    if (_engineReady)
                      AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _agoraService.engine,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          context.tr('preparing_camera'),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 80),
                  const SizedBox(height: 20),
                  Text(
                    context.tr('stream_ended'),
                    style: const TextStyle(
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
                    label: Text(context.tr('go_to_dashboard')),
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
                _isLive ? context.tr('live_tab') : 'Preview',
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
              child: CachedNetworkImage(
                imageUrl: widget.productImage!,
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
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ctrlBtn(Icons.mic, _isMuted ? 'Unmute' : 'Mute', () async {
                  await _agoraService.engine.muteLocalAudioStream(!_isMuted);
                  setState(() => _isMuted = !_isMuted);
                }),
                _ctrlBtn(
                  _isCameraOn ? Icons.videocam : Icons.videocam_off,
                  _isCameraOn ? context.tr('camera') : context.tr('off'),
                  () async {
                    await _agoraService.engine.muteLocalVideoStream(_isCameraOn);
                    setState(() => _isCameraOn = !_isCameraOn);
                  },
                ),
                _ctrlBtn(
                  Icons.switch_camera,
                  context.tr('switch_camera'),
                  () => _agoraService.engine.switchCamera(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isStarting ? null : _startLive,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.red.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isStarting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            context.tr('starting'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_tethering),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('go_live_now'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSection() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
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
                  context.tr('chat_viewers'),
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
