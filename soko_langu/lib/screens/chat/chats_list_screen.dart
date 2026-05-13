import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import '../../services/user_service.dart';
import '../../models/message_model.dart';
import '../../extensions/context_tr.dart';
import 'chat_page.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  void _deleteConversation(BuildContext context, String otherUserId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_conversation')),
        content: Text(context.tr('delete_conversation_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              ChatService().deleteConversation(otherUserId);
              Navigator.pop(ctx);
            },
            child: Text(
              context.tr('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatService = ChatService();
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('chats'))),
      body: StreamBuilder<List<Conversation>>(
        stream: chatService.getConversations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final conversations = snapshot.data ?? [];

          if (conversations.isEmpty) {
            return Center(
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
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conv = conversations[index];
              final otherUserId = conv.participants.firstWhere(
                (id) => id != currentUser?.uid,
                orElse: () =>
                    conv.participants.isNotEmpty ? conv.participants.first : '',
              );

              return _ConversationTile(
                conversation: conv,
                otherUserId: otherUserId,
                onDelete: () => _deleteConversation(context, otherUserId),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String otherUserId;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.otherUserId,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: StreamBuilder<UserProfile?>(
        stream: UserService().streamProfile(otherUserId),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final name = profile?.displayName.isNotEmpty == true
              ? profile!.displayName
              : otherUserId;
          final image = profile?.profileImage;
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green,
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
            title: Text(name),
            subtitle: Text(
              conversation.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "${conversation.lastMessageTime.hour}:${conversation.lastMessageTime.minute.toString().padLeft(2, '0')}",
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
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      "${conversation.unreadCount}",
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatPage(receiverId: otherUserId, receiverName: name),
                ),
              );
            },
            onLongPress: onDelete,
          );
        },
      ),
    );
  }
}
