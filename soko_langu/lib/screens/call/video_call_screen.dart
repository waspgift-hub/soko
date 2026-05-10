import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/agora_config.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';

class VideoCallScreen extends StatefulWidget {
  final String channelName;
  final bool isAudioOnly;

  const VideoCallScreen({
    super.key,
    required this.channelName,
    this.isAudioOnly = false,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  int? _remoteUid;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  RtcEngine? _engine;

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  @override
  void dispose() {
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  Future<void> _initAgora() async {
    if (!widget.isAudioOnly) {
      final camGranted = await requestPermissionWithDialog(context, Permission.camera, 'permission_camera');
      if (!camGranted || !mounted) return;
    }
    if (!mounted) return;
    final micGranted = await requestPermissionWithDialog(context, Permission.microphone, 'permission_microphone');
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

    _engine?.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        setState(() => _isJoined = true);
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        setState(() => _remoteUid = remoteUid);
      },
      onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
        setState(() => _remoteUid = null);
      },
    ));

    final token = await getAgoraToken(channelName: widget.channelName, role: 'broadcaster');
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
                  if (_remoteUid != null && _engine != null)
                    AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine!,
                        canvas: VideoCanvas(uid: _remoteUid),
                        connection: RtcConnection(channelId: widget.channelName),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person, size: 80, color: Colors.white54),
                          const SizedBox(height: 16),
                          Text(context.tr('waiting_for_user'),
                              style: const TextStyle(color: Colors.white54, fontSize: 16)),
                        ],
                      ),
                    ),
                  if (!widget.isAudioOnly && _isJoined && _engine != null)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: SizedBox(
                        width: 100,
                        height: 150,
                        child: AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: _engine!,
                            canvas: VideoCanvas(uid: 0),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.channelName,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? context.tr('unmute') : context.tr('mute'),
                    onTap: () async {
                      await _engine?.muteLocalAudioStream(!_isMuted);
                      setState(() => _isMuted = !_isMuted);
                    },
                  ),
                  if (!widget.isAudioOnly)
                    _controlButton(
                      icon: Icons.switch_camera,
                      label: context.tr('switch_camera'),
                      onTap: () => _engine?.switchCamera(),
                    ),
                  _controlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    label: _isSpeakerOn ? context.tr('speaker') : context.tr('earpiece'),
                    onTap: () async {
                      await _engine?.setEnableSpeakerphone(!_isSpeakerOn);
                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                    },
                  ),
                  _controlButton(
                    icon: Icons.call_end,
                    label: context.tr('end_call'),
                    color: Colors.red,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
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
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
