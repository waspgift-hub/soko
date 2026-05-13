import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'video_call_screen.dart';
import '../../services/call_service.dart';
import '../../extensions/context_tr.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerId;
  final String callerName;
  final String? callerImage;
  final String channelName;
  final String callType;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerImage,
    required this.channelName,
    required this.callType,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with WidgetsBindingObserver {
  final CallService _callService = CallService();
  Timer? _timeoutTimer;
  Timer? _vibeTimer;
  StreamSubscription? _callStatusSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    HapticFeedback.mediumImpact();
    _vibeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) HapticFeedback.mediumImpact();
    });
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      _callService.missCall(widget.callId);
      if (mounted) Navigator.pop(context);
    });
    _listenCallCancelled();
  }

  void _listenCallCancelled() {
    _callStatusSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final status = snap.data()?['status'] as String?;
          if (status == 'cancelled' || status == 'ended') {
            _vibeTimer?.cancel();
            _timeoutTimer?.cancel();
            if (mounted) Navigator.pop(context);
          }
        });
  }

  @override
  void dispose() {
    _callStatusSub?.cancel();
    _vibeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _timeoutTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B4332),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white24,
              backgroundImage: widget.callerImage != null
                  ? NetworkImage(widget.callerImage!)
                  : null,
              child: widget.callerImage == null
                  ? Text(
                      widget.callerName.isNotEmpty
                          ? widget.callerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 48, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              widget.callerName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.callType == 'video'
                  ? context.tr('incoming_video')
                  : context.tr('incoming_voice'),
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const Spacer(flex: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(
                  icon: Icons.call_end,
                  label: context.tr('decline'),
                  color: Colors.red,
                  onTap: () async {
                    await _callService.declineCall(widget.callId);
                    if (mounted) Navigator.pop(context);
                  },
                ),
                _actionButton(
                  icon: widget.callType == 'video'
                      ? Icons.videocam
                      : Icons.phone,
                  label: context.tr('accept'),
                  color: Colors.green,
                  onTap: () async {
                    await _callService.acceptCall(widget.callId);
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoCallScreen(
                            channelName: widget.channelName,
                            isAudioOnly: widget.callType != 'video',
                            callId: widget.callId,
                            remoteName: widget.callerName,
                            remoteImage: widget.callerImage,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
