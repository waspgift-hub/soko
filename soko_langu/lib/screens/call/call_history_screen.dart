import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../extensions/context_tr.dart';
import '../../services/user_service.dart';
import '../../services/call_service.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final UserService _userService = UserService();
  final CallService _callService = CallService();
  final Map<String, UserProfile> _profiles = {};
  String? _activeCallId;
  bool _isCalling = false;

  @override
  void initState() {
    super.initState();
  }

  String _callLabel(String status, String type, String myUid, String callerId) {
    if (status == 'missed') return context.tr('missed');
    if (status == 'declined') return context.tr('declined');
    if (status == 'cancelled') return 'Cancelled';
    if (callerId == myUid) {
      return type == 'video'
          ? context.tr('outgoing_video')
          : context.tr('outgoing_voice');
    }
    return type == 'video'
        ? context.tr('incoming_video_call')
        : context.tr('incoming_voice_call');
  }

  IconData _callIcon(String status, String myUid, String callerId) {
    if (status == 'missed' || status == 'declined') return Icons.call_end_rounded;
    if (callerId == myUid) return Icons.call_made_rounded;
    return Icons.call_received_rounded;
  }

  Color _callColor(String status) {
    if (status == 'missed' || status == 'declined') return Colors.redAccent;
    return const Color(0xFF2D6A4F);
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat('HH:mm').format(time);
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('MMM d').format(time);
  }

  Future<void> _loadProfiles(Set<String> userIds) async {
    final futures = <Future<void>>[];
    for (final uid in userIds) {
      if (!_profiles.containsKey(uid)) {
        futures.add(_userService.getProfile(uid).then((profile) {
          if (profile != null && mounted) {
            setState(() => _profiles[uid] = profile);
          }
        }));
      }
    }
    await Future.wait(futures);
  }

  Future<void> _redialCall(String otherId, String previousType) async {
    try {
      final profile = _profiles[otherId];
      final callId = await _callService.initiateCall(
        calleeId: otherId,
        type: previousType,
        callerName: FirebaseAuth.instance.currentUser?.displayName,
        callerImage: FirebaseAuth.instance.currentUser?.photoURL,
      );
      if (mounted) {
        setState(() {
          _activeCallId = callId;
          _isCalling = true;
        });
      }
      _listenForCallAnswer(callId, isVideo: previousType == 'video', remoteName: profile?.displayName ?? '', remoteImage: profile?.profileImage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('call_failed')} $e')),
        );
      }
    }
  }

  void _listenForCallAnswer(String callId, {required bool isVideo, required String remoteName, String? remoteImage}) {
    _callService.getCallStream(callId).listen((call) {
      if (!mounted || call == null) return;
      if (call['status'] == 'connected') {
        setState(() => _isCalling = false);
        final channelName = call['channelName'] as String;
        context.push(
          '${AppRoutes.videoCall}/$channelName',
          extra: {
            'isAudioOnly': !isVideo,
            'callId': callId,
            'remoteName': remoteName,
            'remoteImage': remoteImage,
          },
        );
      } else if (call['status'] == 'declined' ||
          call['status'] == 'ended' ||
          call['status'] == 'cancelled' ||
          call['status'] == 'missed') {
        setState(() {
          _activeCallId = null;
          _isCalling = false;
        });
        if (mounted) {
          final status = call['status'] as String;
          String msg = context.tr('call_ended');
          if (status == 'declined') msg = 'Call declined';
          else if (status == 'missed') msg = 'No answer';
          else if (status == 'cancelled') msg = 'Call cancelled';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    });
  }

  Future<void> _cancelCall() async {
    if (_activeCallId != null) {
      await _callService.cancelCall(_activeCallId!);
      setState(() {
        _activeCallId = null;
        _isCalling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('call_history'))),
        body: SafeArea(child: Center(child: Text(context.tr('not_logged_in')))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('call_history'))),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('calls')
              .where('participants', arrayContains: user.uid)
              .where('status', whereIn: ['ended', 'declined', 'cancelled', 'missed'])
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }

            final calls = snap.data?.docs ?? [];

            if (calls.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone_missed_rounded, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(context.tr('no_call_history'),
                      style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  ],
                ),
              );
            }

            final otherIds = <String>{};
            for (final doc in calls) {
              final data = doc.data() as Map<String, dynamic>;
              final callerId = data['callerId'] as String? ?? '';
              final calleeId = data['calleeId'] as String? ?? '';
              final otherId = callerId == user.uid ? calleeId : callerId;
              if (otherId.isNotEmpty) otherIds.add(otherId);
            }

            _loadProfiles(otherIds);

            return Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: calls.length,
                  itemBuilder: (context, index) {
                    final doc = calls[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final callerId = data['callerId'] as String? ?? '';
                    final calleeId = data['calleeId'] as String? ?? '';
                    final type = data['type'] as String? ?? 'voice';
                    final status = data['status'] as String? ?? 'ended';
                    final otherId = callerId == user.uid ? calleeId : callerId;
                    final ts = data['createdAt'] as Timestamp?;
                    final time = ts?.toDate() ?? DateTime.now();

                    final profile = _profiles[otherId];
                    final name = profile?.displayName.isNotEmpty == true
                        ? profile!.displayName
                        : context.tr('unknown');
                    final image = profile?.profileImage;

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.green,
                        backgroundImage: image != null ? NetworkImage(image) : null,
                        child: image == null
                            ? Text(name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 18))
                            : null,
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Row(
                        children: [
                          Icon(_callIcon(status, user.uid, callerId),
                            size: 14, color: _callColor(status)),
                          const SizedBox(width: 4),
                          Text(
                            _callLabel(status, type, user.uid, callerId),
                            style: TextStyle(fontSize: 12, color: _callColor(status)),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatTime(time),
                            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          const SizedBox(height: 4),
                          Icon(type == 'video' ? Icons.videocam_rounded : Icons.phone_rounded,
                            size: 18, color: Colors.green[600]),
                        ],
                      ),
                      onTap: () => _redialCall(otherId, type),
                    );
                  },
                ),
                if (_isCalling) _buildCallingOverlay(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCallingOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('calling'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 32),
            TextButton.icon(
              onPressed: _cancelCall,
              icon: const Icon(Icons.call_end, color: Colors.red),
              label: const Text(
                'Cancel',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
