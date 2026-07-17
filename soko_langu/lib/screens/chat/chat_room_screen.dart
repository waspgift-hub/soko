import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../repositories/chat_repository.dart';
import '../../widgets/google_loading.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String? otherUserName;
  const ChatRoomScreen({super.key, required this.roomId, this.otherUserName});
  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}
class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _repo = ChatRepository();
  final _msgCtrl = TextEditingController();
  @override
  void dispose() { _msgCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherUserName ?? 'Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _repo.getMessages(widget.roomId),
              builder: (_, snap) {
                if (!snap.hasData) return const Center(child: GoogleLoading());
                final docs = snap.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(AppInsets.md),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final isMe = d['senderId'] == _repo.currentUid;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? cs.primary : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe ? Radius.zero : null,
                            bottomLeft: isMe ? null : Radius.zero,
                          ),
                        ),
                        child: Text(
                          d['text'] as String? ?? '',
                          style: TextStyle(color: isMe ? cs.onPrimary : cs.onSurface),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppInsets.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: 'Andika ujumbe...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () {
                    if (_msgCtrl.text.trim().isEmpty) return;
                    _repo.sendMessage(widget.roomId, _msgCtrl.text.trim());
                    _msgCtrl.clear();
                  },
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
