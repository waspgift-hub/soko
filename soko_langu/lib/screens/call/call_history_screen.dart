import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../extensions/context_tr.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import 'video_call_screen.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final CallService _callService = CallService();

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
    if (status == 'missed' || status == 'declined') return Icons.call_end;
    if (callerId == myUid) return Icons.call_made;
    return Icons.call_received;
  }

  Color _callColor(String status) {
    if (status == 'missed' || status == 'declined') return Colors.red;
    return Colors.green;
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
            .where(
              'status',
              whereIn: [
                'ended',
                'declined',
                'cancelled',
                'missed',
                'connected',
              ],
            )
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final calls =
              snap.data?.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['callerId'] == user.uid ||
                    data['calleeId'] == user.uid;
              }).toList() ??
              [];

          if (calls.isEmpty) {
            return SafeArea(
              child: Center(
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_missed, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_call_history'),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
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

              return FutureBuilder<UserProfile?>(
                future: UserService().getProfile(otherId),
                builder: (context, profileSnap) {
                  final profile = profileSnap.data;
                  final name = profile?.displayName.isNotEmpty == true
                      ? profile!.displayName
                      : context.tr('unknown');
                  final image = profile?.profileImage;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green,
                        backgroundImage: image != null
                            ? NetworkImage(image)
                            : null,
                        child: image == null
                            ? Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              )
                            : null,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Row(
                        children: [
                          Icon(
                            _callIcon(status, user.uid, callerId),
                            size: 14,
                            color: _callColor(status),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _callLabel(status, type, user.uid, callerId),
                            style: TextStyle(
                              fontSize: 12,
                              color: _callColor(status),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          type == 'video' ? Icons.videocam : Icons.phone,
                          color: Colors.green[600],
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) {
                                final ids = [user.uid, otherId]..sort();
                                return VideoCallScreen(
                                  channelName: 'call_${ids.join("_")}',
                                  isAudioOnly: type != 'video',
                                  remoteName: name,
                                  remoteImage: image,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
