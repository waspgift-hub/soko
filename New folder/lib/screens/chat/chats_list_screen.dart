import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../services/group_service.dart';
import '../../services/presence_service.dart';
import '../../models/group_model.dart';
import '../../models/message_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/verified_badge.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  List<Conversation> _conversations = [];
  List<GroupChat> _groups = [];
  final Map<String, UserProfile> _userProfiles = {};
  bool _loading = true;
  StreamSubscription? _convSub;
  StreamSubscription? _groupSub;

  @override
  void initState() {
    super.initState();
    _convSub = ChatService().getConversations().listen((c) {
      if (mounted) {
        setState(() => _conversations = c);
        _loadAllProfiles();
      }
    });
    _groupSub = GroupService().getGroups().listen((g) {
      if (mounted) {
        setState(() {
          _groups = g;
          _loading = false;
        });
        _loadAllProfiles();
      }
    });
  }

  Future<void> _loadAllProfiles() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final ids = <String>{};
    for (final c in _conversations) {
      for (final p in c.participants) {
        if (p != currentUid) ids.add(p);
      }
    }
    for (final g in _groups) {
      for (final p in g.participantIds) {
        if (p != currentUid) ids.add(p);
      }
    }
    ids.removeAll(_userProfiles.keys);
    if (ids.isEmpty) return;

    final batches = <List<String>>[];
    var batch = <String>[];
    for (final id in ids) {
      batch.add(id);
      if (batch.length == 10) {
        batches.add(batch);
        batch = [];
      }
    }
    if (batch.isNotEmpty) batches.add(batch);

    for (final b in batches) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: b)
            .get();
        if (!mounted) return;
        for (final doc in snap.docs) {
          final data = doc.data();
          _userProfiles[doc.id] = UserProfile(
            uid: doc.id,
            displayName: (data['displayName'] as String?)?.isNotEmpty == true
                ? data['displayName'] as String
                : (data['email'] as String?)?.split('@').first ?? '',
            profileImage: data['profileImage'] as String? ?? '',
            phone: data['phone'] as String? ?? '',
            location: data['location'] as String? ?? '',
            bio: data['bio'] as String? ?? '',
            accountTier: data['accountTier'] as String? ?? 'basic',
            paymentNumbers: Map<String, String>.from(data['paymentNumbers'] ?? {}),
          );
        }
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _convSub?.cancel();
    _groupSub?.cancel();
    super.dispose();
  }

  void _deleteConversation(String otherUserId) {
    ChatService().deleteConversation(otherUserId);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final hasItems = _conversations.isNotEmpty || _groups.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('chats'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.createGroup),
        tooltip: context.tr('create_group'),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const GoogleLoadingPage()
          : !hasItems
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                      const SizedBox(height: 16),
                      Text(context.tr('no_conversations'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final conv = _conversations[index];
                    final otherUserId = conv.participants.firstWhere(
                      (id) => id != currentUser?.uid,
                      orElse: () => conv.participants.isNotEmpty ? conv.participants.first : '',
                    );
                    final profile = _userProfiles[otherUserId];
                    final storedName = conv.participantNames[otherUserId];
                    final name = profile?.displayName.isNotEmpty == true 
                        ? profile!.displayName 
                        : (storedName?.isNotEmpty == true 
                            ? storedName! 
                            : (otherUserId.length > 8 ? '${otherUserId.substring(0, 8)}...' : otherUserId));
                    final image = profile?.profileImage;
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              backgroundImage: image != null && image.isNotEmpty ? NetworkImage(image) : null,
                              child: image == null || image.isEmpty ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: StreamBuilder<bool>(
                                stream: PresenceService().isOnline(otherUserId),
                                builder: (context, snap) {
                                  final online = snap.data ?? false;
                                  return Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: online ? Colors.greenAccent : Colors.grey,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            VerifiedBadge(tier: profile?.accountTier ?? 'basic', size: 14),
                          ],
                        ),
                        subtitle: Text(conv.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_formatTime(conv.lastMessageTime), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                            if (conv.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                                child: Text("${conv.unreadCount}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                          ],
                        ),
                        onTap: () => context.push('${AppRoutes.chat}/$otherUserId', extra: {'name': name}),
                        onLongPress: () => _showOptions(context, conv, otherUserId),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final hour = time.hour.toString().padLeft(2, '0');
      final min = time.minute.toString().padLeft(2, '0');
      return '$hour:$min';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    }
    return '${time.day}/${time.month}';
  }

  void _showOptions(BuildContext context, Conversation conv, String otherUserId) {
    final chatService = ChatService();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(conv.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(conv.isPinned ? context.tr('unpin_chat') : context.tr('pin_chat')),
              onTap: () {
                Navigator.pop(ctx);
                conv.isPinned ? chatService.unpinConversation(otherUserId) : chatService.pinConversation(otherUserId);
              },
            ),
            ListTile(
              leading: Icon(conv.isMuted ? Icons.notifications_off : Icons.notifications),
              title: Text(conv.isMuted ? context.tr('unmute_chat') : context.tr('mute_chat')),
              onTap: () {
                Navigator.pop(ctx);
                conv.isMuted ? chatService.unmuteConversation(otherUserId) : chatService.muteConversation(otherUserId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: Text(context.tr('block_user'), style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                chatService.blockUser(otherUserId);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('user_blocked'))));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(context.tr('delete_chat'), style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteConversation(otherUserId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

