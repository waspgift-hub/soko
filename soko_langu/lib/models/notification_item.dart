class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime timestamp;
  final String? otherUserId;
  final String? otherUserName;
  final String? otherUserImage;
  final String? productId;
  final String? productImage;
  final bool isRead;
  final int unreadCount;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.otherUserId,
    this.otherUserName,
    this.otherUserImage,
    this.productId,
    this.productImage,
    this.isRead = false,
    this.unreadCount = 0,
  });
}
