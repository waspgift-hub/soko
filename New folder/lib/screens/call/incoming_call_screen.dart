import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:vibration/vibration.dart';
import '../../services/call_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

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
    _startRingtone();
    _startVibration();
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      _stopAll();
      _callService.missCall(widget.callId);
      if (mounted) Navigator.pop(context);
    });
    _listenCallCancelled();
  }

  Future<void> _startRingtone() async {
    try {
      await FlutterRingtonePlayer().playRingtone(
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('Ringtone error: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await FlutterRingtonePlayer().stop();
    } catch (_) {}
  }

  Future<void> _startVibration() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;
    final hasPattern = await Vibration.hasCustomVibrationsSupport();
    if (hasPattern) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000, 500, 1000], repeat: 3);
    } else {
      _vibeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) Vibration.vibrate(duration: 500);
      });
    }
  }

  void _stopVibration() {
    Vibration.cancel();
    _vibeTimer?.cancel();
  }

  void _stopAll() {
    _stopRingtone();
    _stopVibration();
    _timeoutTimer?.cancel();
    _callStatusSub?.cancel();
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
            _stopAll();
            if (mounted) Navigator.pop(context);
          }
        });
  }

  @override
  void dispose() {
    _stopAll();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image with blur
          if (widget.callerImage != null && widget.callerImage!.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                widget.callerImage!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0D1B12).withOpacity(0.85),
                    const Color(0xFF0D1B12).withOpacity(0.95),
                    const Color(0xFF0D1B12),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Caller avatar
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white12,
                    backgroundImage: widget.callerImage != null && widget.callerImage!.isNotEmpty
                        ? NetworkImage(widget.callerImage!)
                        : null,
                    child: widget.callerImage == null || widget.callerImage!.isEmpty
                        ? Text(
                            widget.callerName.isNotEmpty
                                ? widget.callerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 48,
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.callType == 'video'
                      ? context.tr('incoming_video')
                      : context.tr('incoming_voice'),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white60,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(flex: 2),
                // Accept/Decline buttons
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 40,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionButton(
                        icon: Icons.call_end_rounded,
                        label: context.tr('decline'),
                        color: Colors.redAccent,
                        onTap: () async {
                          _stopAll();
                          await FlutterCallkitIncoming.endCall(widget.callId);
                          await _callService.declineCall(widget.callId);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                      _actionButton(
                        icon: widget.callType == 'video'
                            ? Icons.videocam_rounded
                            : Icons.phone_rounded,
                        label: context.tr('accept'),
                        color: const Color(0xFF2D6A4F),
                        onTap: () async {
                          _stopAll();
                          await FlutterCallkitIncoming.endCall(widget.callId);
                          await _callService.acceptCall(widget.callId);
                          if (context.mounted) {
                            context.replace(AppRoutes.videoCall, extra: {
                              'callId': widget.callId,
                              'callType': widget.callType,
                              'remoteName': widget.callerName,
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
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

