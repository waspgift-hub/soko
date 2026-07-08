import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_dimens.dart';
import '../../repositories/chat_repository.dart';
import '../../app/routes.dart';

class ChatInboxScreen extends StatelessWidget {
  const ChatInboxScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repo = ChatRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: StreamBuilder(
        stream: repo.getChats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final chats = snapshot.data!.docs;
          if (chats.isEmpty) return Center(child: Text('No conversations', style: TextStyle(color: cs.onSurfaceVariant)));
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final data = chats[i].data() as Map<String, dynamic>;
              return ListTile(
                title: Text('Chat ${i + 1}', style: TextStyle(color: cs.onSurface)),
                subtitle: Text(data['lastMessage'] ?? '', style: TextStyle(color: cs.onSurfaceVariant)),
                onTap: () => context.push('/chat/${chats[i].id}'),
              );
            },
          );
        },
      ),
    );
  }
}
