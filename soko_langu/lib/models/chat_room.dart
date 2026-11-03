class ChatRoom {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime? lastTimestamp;
  final int unreadCountBuyer;
  final int unreadCountSeller;
  final Map<String, int> unreadCounts;
  final String? productId;
  final String? productTitle;
  final String? buyerId;
  final String? sellerId;
  final List<String> pinnedBy;
  final List<String> mutedBy;
  final List<String> archivedBy;
  final List<String> favouritedBy;

  ChatRoom({
    required this.id,
    required this.participants,
    this.lastMessage = '',
    this.lastTimestamp,
    this.unreadCountBuyer = 0,
    this.unreadCountSeller = 0,
    this.unreadCounts = const {},
    this.productId,
    this.productTitle,
    this.buyerId,
    this.sellerId,
    this.pinnedBy = const [],
    this.mutedBy = const [],
    this.archivedBy = const [],
    this.favouritedBy = const [],
  });

  bool isPinned(String uid) => pinnedBy.contains(uid);
  bool isMuted(String uid) => mutedBy.contains(uid);
  bool isArchived(String uid) => archivedBy.contains(uid);
  bool isFavourited(String uid) => favouritedBy.contains(uid);

  factory ChatRoom.fromMap(String id, Map<String, dynamic> data) {
    final counts = <String, int>{};
    final raw = data['unread_counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) counts[k.toString()] = v.toInt();
      });
    }
    final oldBuyer = (data['unread_count_buyer'] as num?)?.toInt() ?? 0;
    final oldSeller = (data['unread_count_seller'] as num?)?.toInt() ?? 0;
    return ChatRoom(
      id: id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['last_message'] as String? ?? '',
      lastTimestamp: (data['last_timestamp'] as dynamic)?.toDate(),
      unreadCountBuyer: oldBuyer,
      unreadCountSeller: oldSeller,
      unreadCounts: counts,
      productId: data['product_id'] as String?,
      productTitle: data['product_title'] as String?,
      buyerId: data['buyer_id'] as String?,
      sellerId: data['seller_id'] as String?,
      pinnedBy: List<String>.from(data['pinned_by'] ?? []),
      mutedBy: List<String>.from(data['muted_by'] ?? []),
      archivedBy: List<String>.from(data['archived_by'] ?? []),
      favouritedBy: List<String>.from(data['favourited_by'] ?? []),
    );
  }

  int unreadCountFor(String uid) {
    if (unreadCounts.isNotEmpty) return unreadCounts[uid] ?? 0;
    final isBuyer = buyerId == uid;
    return isBuyer ? unreadCountBuyer : unreadCountSeller;
  }
}
