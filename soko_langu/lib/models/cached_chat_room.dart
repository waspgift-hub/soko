import 'package:hive/hive.dart';
import 'chat_room.dart';

part 'cached_chat_room.g.dart';

@HiveType(typeId: 2)
class CachedChatRoom {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final List<String> participants;

  @HiveField(2)
  final String lastMessage;

  @HiveField(3)
  final int lastTimestampMillis;

  @HiveField(4)
  final int unreadCountBuyer;

  @HiveField(5)
  final int unreadCountSeller;

  @HiveField(6)
  final String? productId;

  @HiveField(7)
  final String? productTitle;

  CachedChatRoom({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastTimestampMillis,
    required this.unreadCountBuyer,
    required this.unreadCountSeller,
    this.productId,
    this.productTitle,
  });

  factory CachedChatRoom.fromChatRoom(ChatRoom room) => CachedChatRoom(
        id: room.id,
        participants: room.participants,
        lastMessage: room.lastMessage,
        lastTimestampMillis: room.lastTimestamp?.millisecondsSinceEpoch ?? 0,
        unreadCountBuyer: room.unreadCountBuyer,
        unreadCountSeller: room.unreadCountSeller,
        productId: room.productId,
        productTitle: room.productTitle,
      );

  ChatRoom toChatRoom() => ChatRoom(
        id: id,
        participants: participants,
        lastMessage: lastMessage,
        lastTimestamp: lastTimestampMillis > 0
            ? DateTime.fromMillisecondsSinceEpoch(lastTimestampMillis)
            : null,
        unreadCountBuyer: unreadCountBuyer,
        unreadCountSeller: unreadCountSeller,
        productId: productId,
        productTitle: productTitle,
      );
}