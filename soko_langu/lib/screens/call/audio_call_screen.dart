import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/agora_service.dart';
import '../../services/agora_config.dart';
import '../../services/call_service.dart';
import '../../utils/helpers.dart';

class AudioCallScreen extends StatefulWidget {
  final String channelName;
  final String? callId;
  final String? remoteName;
  final String? remoteImage;

  const AudioCallScreen({
    super.key,
    required this.channelName,
    this.callId,
    this.remoteName,
    this.remoteImage,
  });

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  final CallService _callService = CallService();
  final AgoraService _agoraService = AgoraService();
  int? _remoteUid;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  StreamSubscription? _callStatusSub;

  @override
  void initState() {
    super.initState();
    _initAgora();
    _listenCallStatus();
  }

  @override
  void dispose() {
    _callStatusSub?.cancel();
    _agoraService.dispose();
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
      if (status == 'ended' || status == 'declined' || status == 'cancelled') {
        if (mounted) Navigator.pop(context);
      }
    });
  }

  Future<void> _initAgora() async {
    try {
      final micGranted = await requestPermissionWithDialog(
        context, Permission.microphone, 'permission_microphone',
      );
      if (!micGranted || !mounted) return;

      await _agoraService.initialize();
      await _agoraService.engine.enableAudio();
      await _agoraService.engine.disableVideo();

      _agoraService.engine.registerEventHandler(RtcEngineEventHandler(
        onUserJoined: (RtcConnection connection, int uid, int elapsed) {
          setState(() => _remoteUid = uid);
        },
        onUserOffline: (RtcConnection connection, int uid, UserOfflineReasonType reason) {
          setState(() => _remoteUid = null);
          if (widget.callId != null) _callService.endCall(widget.callId!);
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        },
      ));

      final token = await getAgoraToken(
        channelName: widget.channelName, role: 'broadcaster',
      );

      await _agoraService.engine.joinChannel(
        token: token,
        channelId: widget.channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      debugPrint('AudioCall init error: $e');
    }
  }

  void _endCall() async {
    if (widget.callId != null) await _callService.endCall(widget.callId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white12,
              backgroundImage: widget.remoteImage != null
                  ? NetworkImage(widget.remoteImage!)
                  : null,
              child: widget.remoteImage == null
                  ? const Icon(Icons.phone_rounded, size: 48, color: Colors.white54)
                  : null,
            ),
            const SizedBox(height: 20),
            Text(
              widget.remoteName ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _remoteUid != null ? 'Connected' : 'Calling...',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _controlButton(
                  icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  onTap: () async {
                    await _agoraService.engine.muteLocalAudioStream(!_isMuted);
                    setState(() => _isMuted = !_isMuted);
                  },
                ),
                _controlButton(
                  icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                  onTap: () async {
                    await _agoraService.engine.setEnableSpeakerphone(!_isSpeakerOn);
                    setState(() => _isSpeakerOn = !_isSpeakerOn);
                  },
                ),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: _endCall,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}
