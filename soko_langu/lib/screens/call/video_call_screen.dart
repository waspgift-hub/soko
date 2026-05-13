import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  int? _remoteUid;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _callEnded = false;
  RtcEngine? _engine;
  StreamSubscription? _callStatusSub;
  Timer? _durationTimer;
  int _durationSeconds = 0;

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
  }

  @override
  void dispose() {
    _callStatusSub?.cancel();
    _durationTimer?.cancel();
    _engine?.leaveChannel();
    _engine?.release();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
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
          if (status == 'ended' ||
              status == 'declined' ||
              status == 'cancelled') {
            _callEnded = true;
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
    if (!widget.isAudioOnly) {
      final camGranted = await requestPermissionWithDialog(
        context,
        Permission.camera,
        'permission_camera',
      );
      if (!camGranted || !mounted) return;
    }
    if (!mounted) return;
    final micGranted = await requestPermissionWithDialog(
      context,
      Permission.microphone,
      'permission_microphone',
    );
    if (!micGranted) return;

    _engine = createAgoraRtcEngine();
    await _engine?.initialize(RtcEngineContext(appId: agoraAppId));

    if (widget.isAudioOnly) {
      await _engine?.enableAudio();
      await _engine?.disableVideo();
    } else {
      await _engine?.enableVideo();
      await _engine?.startPreview();
    }

    _engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          setState(() => _isJoined = true);
          _startDurationTimer();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          setState(() => _remoteUid = remoteUid);
        },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              setState(() => _remoteUid = null);
              _callEnded = true;
              _durationTimer?.cancel();
              if (widget.callId != null) {
                _callService.endCall(widget.callId!);
              }
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) Navigator.pop(context);
              });
            },
      ),
    );

    final token = await getAgoraToken(
      channelName: widget.channelName,
      role: 'broadcaster',
    );
    await _engine?.joinChannel(
      token: token,
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  void _endCall() async {
    _durationTimer?.cancel();
    if (widget.callId != null) {
      await _callService.endCall(widget.callId!);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (_remoteUid != null &&
                      _engine != null &&
                      !widget.isAudioOnly)
                    AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine!,
                        canvas: VideoCanvas(uid: _remoteUid),
                        connection: RtcConnection(
                          channelId: widget.channelName,
                        ),
                      ),
                    )
                  else
                    _buildWaitingUI(),
                  if (!widget.isAudioOnly && _isJoined && _engine != null)
                    Positioned(
                      top: 80,
                      right: 20,
                      child: SizedBox(
                        width: 100,
                        height: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: _engine!,
                              canvas: VideoCanvas(uid: 0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(top: 20, left: 0, right: 0, child: _buildTopBar()),
                ],
              ),
            ),
            _buildControls(),
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
          CircleAvatar(
            radius: widget.isAudioOnly ? 60 : 40,
            backgroundColor: Colors.white24,
            backgroundImage: widget.remoteImage != null
                ? NetworkImage(widget.remoteImage!)
                : null,
            child: widget.remoteImage == null
                ? Icon(
                    widget.isAudioOnly ? Icons.phone : Icons.person,
                    size: widget.isAudioOnly ? 60 : 40,
                    color: Colors.white54,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            widget.remoteName ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _remoteUid != null
                ? context.tr('connected')
                : (_isJoined
                      ? context.tr('ringing')
                      : context.tr('connecting')),
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
                color: Colors.green.withValues(alpha: value),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildTopBar() {
    return Column(
      children: [
        if (_isJoined && _remoteUid != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatDuration(_durationSeconds),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (widget.isAudioOnly && _isJoined) ...[
          const SizedBox(height: 12),
          Text(
            widget.remoteName ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        0,
        30,
        0,
        30 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            onTap: () async {
              await _engine?.muteLocalAudioStream(!_isMuted);
              setState(() => _isMuted = !_isMuted);
            },
          ),
          if (!widget.isAudioOnly)
            _controlButton(
              icon: Icons.switch_camera,
              label: context.tr('flip'),
              onTap: () => _engine?.switchCamera(),
            ),
          _controlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
            onTap: () async {
              await _engine?.setEnableSpeakerphone(!_isSpeakerOn);
              setState(() => _isSpeakerOn = !_isSpeakerOn);
            },
          ),
          _controlButton(
            icon: Icons.call_end,
            label: 'End',
            color: Colors.red,
            onTap: _endCall,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color ?? Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
