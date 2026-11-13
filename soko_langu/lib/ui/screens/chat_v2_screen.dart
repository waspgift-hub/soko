import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../models/chat_room.dart';
import '../../services/chat_service.dart';

class ChatV2Screen extends StatelessWidget {
  const ChatV2Screen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mazungumzo')),
        body: const Center(child: Text('Ingia ili kuona mazungumzo.')),
      );
    }
    final service = ChatService();

    return Scaffold(
      appBar: AppBar(title: const Text('Mazungumzo')),
      body: StreamBuilder<List<ChatRoom>>(
        stream: service.getRooms(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rooms = snap.data ?? const [];
          if (rooms.isEmpty) {
            return const Center(child: Text('Huna mazungumzo bado.'));
          }
          return ListView.separated(
            itemCount: rooms.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _RoomRow(room: rooms[i], uid: uid),
          );
        },
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.uid});

  final ChatRoom room;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final unread = room.unreadCountFor(uid);
    return ListTile(
      title: Text(room.productTitle ?? 'Mazungumzo', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(room.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: unread > 0 ? Text('$unread') : null,
      onTap: () => context.push(AppRoutes.chat, extra: room),
    );
  }
}
