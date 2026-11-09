import 'package:cloud_firestore/cloud_firestore.dart';

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
    return ChatRoom(
      id: id,
      participants: _stringList(data['participants']),
      lastMessage: _string(data['last_message']) ?? '',
      lastTimestamp: _timestamp(data['last_timestamp']),
      unreadCountBuyer: _int(data['unread_count_buyer']),
      unreadCountSeller: _int(data['unread_count_seller']),
      unreadCounts: counts,
      productId: _string(data['product_id']),
      productTitle: _string(data['product_title']),
      buyerId: _string(data['buyer_id']),
      sellerId: _string(data['seller_id']),
      pinnedBy: _stringList(data['pinned_by']),
      mutedBy: _stringList(data['muted_by']),
      archivedBy: _stringList(data['archived_by']),
      favouritedBy: _stringList(data['favourited_by']),
    );
  }

  // Legacy rooms were written by several clients with inconsistent types.
  // Coercing instead of casting keeps one bad document from throwing and
  // blanking the whole inbox.

  static String? _string(Object? raw) => raw is String ? raw : null;

  static int _int(Object? raw) => raw is num ? raw.toInt() : 0;

  static List<String> _stringList(Object? raw) {
    if (raw is! Iterable) return const [];
    return raw.whereType<String>().toList();
  }

  static DateTime? _timestamp(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  int unreadCountFor(String uid) {
    if (unreadCounts.isNotEmpty) return unreadCounts[uid] ?? 0;
    final isBuyer = buyerId == uid;
    return isBuyer ? unreadCountBuyer : unreadCountSeller;
  }
}
