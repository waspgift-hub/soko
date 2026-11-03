class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime? timestamp;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.timestamp,
    this.isRead = false,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    return ChatMessage(
      id: id,
      senderId: data['sender_id'] as String? ?? '',
      text: data['text'] as String? ?? '',
      timestamp: (data['timestamp'] as dynamic)?.toDate(),
      isRead: data['is_read'] as bool? ?? false,
    );
  }
}
