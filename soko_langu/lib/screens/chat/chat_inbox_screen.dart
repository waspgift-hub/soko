import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../services/local_cache_service.dart';
import '../../models/chat_room.dart';
import '../../extensions/context_tr.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final Map<String, String> _userNames = {};
  final Map<String, String> _userPhotos = {};

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  void _loadCached() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final cached = LocalCacheService.getCachedRoomsForUser(uid);
    for (final room in cached) {
      final otherId = room.participants.where((p) => p != uid).firstOrNull;
      if (otherId != null) _fetchUser(otherId);
    }
  }

  Future<void> _fetchUser(String uid) async {
    if (_userNames.containsKey(uid)) return;
    final profile = await _userService.getProfile(uid);
    if (profile != null && mounted) {
      setState(() {
        _userNames[uid] = profile.displayName;
        _userPhotos[uid] = profile.profileImage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('chats')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<List<ChatRoom>>(
        stream: _chatService.getRooms(),
        builder: (context, snap) {
          final rooms = snap.data ?? [];
          if (rooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(context.tr('no_conversations'), style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            itemCount: rooms.length,
            itemBuilder: (_, i) {
              final room = rooms[i];
              final otherId = room.participants.where((p) => p != uid).firstOrNull ?? '';
              if (otherId.isEmpty) return const SizedBox.shrink();
              _fetchUser(otherId);
              final name = _userNames[otherId] ?? otherId.substring(0, 8);
              final photo = _userPhotos[otherId] ?? '';

              return _ChatListTile(
                name: name,
                photo: photo,
                lastMessage: room.lastMessage,
                lastTimestamp: room.lastTimestamp,
                unreadCount: room.lastTimestamp != null ? 1 : 0,
                onTap: () async {
                  await _chatService.getOrCreateRoom(otherUserId: otherId);
                  if (context.mounted) {
                    context.push('/chat/$otherId', extra: {
                      'name': name,
                      'productId': room.productId ?? '',
                      'productTitle': room.productTitle ?? '',
                    });
                  }
                },
                cs: cs,
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  final String name;
  final String photo;
  final String? lastMessage;
  final DateTime? lastTimestamp;
  final int unreadCount;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _ChatListTile({
    required this.name,
    required this.photo,
    this.lastMessage,
    this.lastTimestamp,
    this.unreadCount = 0,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                  backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                  child: photo.isEmpty
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.primary))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface)),
                          ),
                          if (lastTimestamp != null)
                            Text(
                              _formatTime(context, lastTimestamp!),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage ?? context.tr('no_messages'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                            ),
                          ),
                          if (unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('$unreadCount', style: TextStyle(fontSize: 11, color: cs.surface, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 1) return context.tr('yesterday');
    return '${dt.day}/${dt.month}';
  }
}
