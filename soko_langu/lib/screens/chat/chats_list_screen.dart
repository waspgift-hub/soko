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
            displayName: data['displayName'] as String? ?? '',
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

  List<_ChatItem> _buildUnifiedList() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final items = <_ChatItem>[];

    for (final conv in _conversations) {
      final otherUserId = conv.participants.firstWhere(
        (id) => id != currentUid,
        orElse: () => conv.participants.isNotEmpty ? conv.participants.first : '',
      );
      items.add(_ChatItem(
        type: _ChatType.conversation,
        id: conv.id,
        otherUserId: otherUserId,
        lastMessage: conv.lastMessage,
        lastMessageTime: conv.lastMessageTime,
        unreadCount: conv.unreadCount,
        profile: _userProfiles[otherUserId],
      ));
    }

    for (final group in _groups) {
      items.add(_ChatItem(
        type: _ChatType.group,
        id: group.id,
        group: group,
        lastMessage: group.lastMessage,
        lastMessageTime: group.lastMessageTime,
        unreadCount: group.unreadCount,
      ));
    }

    items.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final unifiedList = _buildUnifiedList();
    final hasItems = unifiedList.isNotEmpty;

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
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_conversations'),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('chat_empty'),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: unifiedList.length,
              itemBuilder: (context, index) {
                final item = unifiedList[index];
                if (item.type == _ChatType.group) {
                  return _GroupTile(
                    group: item.group!,
                    profiles: _userProfiles,
                    currentUid: currentUser?.uid ?? '',
                  );
                }
                return _ConversationTile(
                  conversation: _conversations.firstWhere(
                    (c) => c.id == item.id,
                    orElse: () => _conversations.first,
                  ),
                  otherUserId: item.otherUserId,
                  profile: item.profile,
                  onDelete: () => _deleteConversation(item.otherUserId),
                );
              },
            ),
    );
  }
}

enum _ChatType { conversation, group }

class _ChatItem {
  final _ChatType type;
  final String id;
  final String otherUserId;
  final GroupChat? group;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final UserProfile? profile;

  _ChatItem({
    required this.type,
    required this.id,
    this.otherUserId = '',
    this.group,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.profile,
  });
}

class _GroupTile extends StatelessWidget {
  final GroupChat group;
  final Map<String, UserProfile> profiles;
  final String currentUid;

  const _GroupTile({
    required this.group,
    required this.profiles,
    required this.currentUid,
  });

  String _getMemberNames() {
    final names = <String>[];
    for (final pid in group.participantIds.take(3)) {
      if (pid == currentUid) continue;
      final p = profiles[pid];
      if (p != null && p.displayName.isNotEmpty) {
        names.add(p.displayName);
      }
    }
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final memberNames = _getMemberNames();
    final subtitle = group.lastMessage.isNotEmpty
        ? group.lastMessage
        : memberNames.isNotEmpty
            ? '${group.participantIds.length} members: $memberNames'
            : '${group.participantIds.length} members';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
          backgroundImage: group.imageUrl.isNotEmpty
              ? NetworkImage(group.imageUrl)
              : null,
          child: group.imageUrl.isEmpty
              ? const Icon(Icons.group, color: Colors.white)
              : null,
        ),
        title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: group.unreadCount > 0
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${group.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              )
            : null,
        onTap: () => context.push('${AppRoutes.groupChat}/${group.id}'),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String otherUserId;
  final UserProfile? profile;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.otherUserId,
    this.profile,
    required this.onDelete,
  });

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

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : otherUserId;
    final image = profile?.profileImage;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: image != null && image.isNotEmpty
                  ? NetworkImage(image)
                  : null,
              child: image == null || image.isEmpty
                  ? Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
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
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            VerifiedBadge(tier: profile?.accountTier ?? 'basic', size: 14),
          ],
        ),
        subtitle: Text(
          conversation.lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatTime(conversation.lastMessageTime),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (conversation.unreadCount > 0)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  "${conversation.unreadCount}",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
        onTap: () => context.push(
          '${AppRoutes.chat}/$otherUserId',
          extra: {'name': name},
        ),
        onLongPress: onDelete,
      ),
    );
  }
}
