class ChatRoom {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime? lastTimestamp;
  final int unreadCountBuyer;
  final int unreadCountSeller;
  final String? productId;
  final String? productTitle;

  ChatRoom({
    required this.id,
    required this.participants,
    this.lastMessage = '',
    this.lastTimestamp,
    this.unreadCountBuyer = 0,
    this.unreadCountSeller = 0,
    this.productId,
    this.productTitle,
  });

  factory ChatRoom.fromMap(String id, Map<String, dynamic> data) {
    return ChatRoom(
      id: id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['last_message'] as String? ?? '',
      lastTimestamp: (data['last_timestamp'] as dynamic)?.toDate(),
      unreadCountBuyer: (data['unread_count_buyer'] as num?)?.toInt() ?? 0,
      unreadCountSeller: (data['unread_count_seller'] as num?)?.toInt() ?? 0,
      productId: data['product_id'] as String?,
      productTitle: data['product_title'] as String?,
    );
  }
}
