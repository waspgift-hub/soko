import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/agora_service.dart';
import '../../services/agora_config.dart';
import '../../services/call_service.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';

class VideoCallScreen extends StatefulWidget {
  final String channelName;
  final bool isAudioOnly;
  final String? callId;
  final String? remoteName;
  final String? remoteImage;

  const VideoCallScreen({
    super.key,
    required this.channelName,
    this.isAudioOnly = false,
    this.callId,
    this.remoteName,
    this.remoteImage,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final CallService _callService = CallService();
  final AgoraService _agoraService = AgoraService();
  int? _remoteUid;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _showControls = true;
  StreamSubscription? _callStatusSub;
  Timer? _durationTimer;
  Timer? _controlsTimer;
  int _durationSeconds = 0;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!widget.isAudioOnly) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _initAgora();
    _listenCallStatus();
    _startControlsTimer();
  }

  @override
  void dispose() {
    _callStatusSub?.cancel();
    _durationTimer?.cancel();
    _controlsTimer?.cancel();
    _agoraService.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startControlsTimer();
  }

  void _listenCallStatus() {
    if (widget.callId == null) return;
    _callStatusSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final status = snap.data()?['status'] as String?;
      if (status == 'ended' || status == 'declined' || status == 'cancelled') {
        _durationTimer?.cancel();
        if (mounted) Navigator.pop(context);
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  String _formatDuration(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _initAgora() async {
    try {
      if (!widget.isAudioOnly) {
        final camGranted = await requestPermissionWithDialog(
          context, Permission.camera, 'permission_camera',
        );
        if (!camGranted || !mounted) return;
      }
      if (!mounted) return;
      final micGranted = await requestPermissionWithDialog(
        context, Permission.microphone, 'permission_microphone',
      );
      if (!micGranted || !mounted) return;

      await _agoraService.initialize();
      final engine = _agoraService.engine;

      if (widget.isAudioOnly) {
        await engine.enableAudio();
        await engine.disableVideo();
      } else {
        await engine.enableVideo();
        await engine.startPreview();
      }

      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() => _isJoined = true);
          _startDurationTimer();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          setState(() => _remoteUid = remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          setState(() => _remoteUid = null);
          _durationTimer?.cancel();
          if (widget.callId != null) _callService.endCall(widget.callId!);
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) async {
          final newToken = await getAgoraToken(
            channelName: widget.channelName, role: 'broadcaster',
          );
          if (newToken.isNotEmpty) engine.renewToken(newToken);
        },
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
          if (state == ConnectionStateType.connectionStateReconnecting && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('reconnecting'))),
            );
          }
          if (state == ConnectionStateType.connectionStateConnected && mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        },
      ));

      final token = await getAgoraToken(
        channelName: widget.channelName, role: 'broadcaster',
      );
      await engine.joinChannel(
        token: token,
        channelId: widget.channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      debugPrint('initAgora error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('call_error')} $e")),
        );
        setState(() => _initFailed = true);
      }
    }
  }

  void _endCall() async {
    _durationTimer?.cancel();
    if (widget.callId != null) await _callService.endCall(widget.callId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initFailed)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Could not connect to call',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ))
            else if (_remoteUid != null && !widget.isAudioOnly)
              AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _agoraService.engine,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection: RtcConnection(channelId: widget.channelName),
                ),
              )
            else
              _buildWaitingUI(),

            if (!widget.isAudioOnly && _isJoined)
              Positioned(
                top: 60, left: 16,
                child: GestureDetector(
                  onTap: _toggleControls,
                  child: SizedBox(
                    width: 90, height: 140,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _agoraService.engine,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            if (_showControls) ...[
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 12, bottom: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _isJoined && _remoteUid != null
                          ? _formatDuration(_durationSeconds)
                          : widget.isAudioOnly
                              ? context.tr('calling')
                              : context.tr('connecting'),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                    ),
                  ),
                  child: Column(
                    children: [
                      if (widget.isAudioOnly && _isJoined) ...[
                        Text(widget.remoteName ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _controlButton(
                            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            label: _isMuted ? 'Unmute' : 'Mute',
                            onTap: () async {
                              await _agoraService.engine.muteLocalAudioStream(!_isMuted);
                              setState(() => _isMuted = !_isMuted);
                            },
                          ),
                          if (!widget.isAudioOnly)
                            _controlButton(
                              icon: Icons.flip_camera_android_rounded,
                              label: context.tr('flip'),
                              onTap: () => _agoraService.engine.switchCamera(),
                            ),
                          _controlButton(
                            icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                            label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                            onTap: () async {
                              await _agoraService.engine.setEnableSpeakerphone(!_isSpeakerOn);
                              setState(() => _isSpeakerOn = !_isSpeakerOn);
                            },
                          ),
                          _endButton(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white12,
              backgroundImage: widget.remoteImage != null ? NetworkImage(widget.remoteImage!) : null,
              child: widget.remoteImage == null
                  ? Icon(widget.isAudioOnly ? Icons.phone_rounded : Icons.person_rounded,
                      size: 48, color: Colors.white54)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.remoteName ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _remoteUid != null
                ? context.tr('connected')
                : (_isJoined ? context.tr('ringing') : context.tr('connecting')),
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          if (_isJoined && _remoteUid != null && widget.isAudioOnly)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _audioWave(),
            ),
        ],
      ),
    );
  }

  Widget _audioWave() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 1.0),
          duration: Duration(milliseconds: 600 + i * 150),
          builder: (context, value, child) {
            return Container(
              width: 6,
              height: 30 * value,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F).withValues(alpha: value),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _controlButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _endButton() {
    return GestureDetector(
      onTap: _endCall,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent, shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                  blurRadius: 12, offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          const Text('End', style: TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }
}
