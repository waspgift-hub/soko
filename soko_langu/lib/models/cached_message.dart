import 'package:hive/hive.dart';
import 'message_model.dart';

class CachedMessage extends HiveObject {
  final String id;
  final String roomId;
  final String senderId;
  final String receiverId;
  final String content;
  final int timestampMs;
  final bool isRead;
  final bool isDelivered;
  final bool isEdited;
  final String? productId;
  final String? productName;
  final String? replyTo;
  final String? replyToContent;
  final String? replyToSender;
  final String messageType;
  final bool isDeletedForEveryone;

  CachedMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestampMs,
    this.isRead = false,
    this.isDelivered = false,
    this.isEdited = false,
    this.productId,
    this.productName,
    this.replyTo,
    this.replyToContent,
    this.replyToSender,
    this.messageType = 'text',
    this.isDeletedForEveryone = false,
  });

  factory CachedMessage.fromMessage(String roomId, Message msg) {
    return CachedMessage(
      id: msg.id,
      roomId: roomId,
      senderId: msg.senderId,
      receiverId: msg.receiverId,
      content: msg.content,
      timestampMs: msg.timestamp.millisecondsSinceEpoch,
      isRead: msg.isRead,
      isDelivered: msg.isDelivered,
      isEdited: msg.isEdited,
      productId: msg.productId,
      productName: msg.productName,
      replyTo: msg.replyTo,
      replyToContent: msg.replyToContent,
      replyToSender: msg.replyToSender,
      messageType: msg.messageType,
      isDeletedForEveryone: msg.isDeletedForEveryone,
    );
  }

  Message toMessage() {
    return Message(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      isRead: isRead,
      isDelivered: isDelivered,
      isEdited: isEdited,
      productId: productId,
      productName: productName,
      replyTo: replyTo,
      replyToContent: replyToContent,
      replyToSender: replyToSender,
      messageType: messageType,
      isDeletedForEveryone: isDeletedForEveryone,
    );
  }
}

class CachedMessageAdapter extends TypeAdapter<CachedMessage> {
  @override
  final int typeId = 1;

  @override
  CachedMessage read(BinaryReader reader) {
    final fields = reader.readMap().cast<int, dynamic>();
    return CachedMessage(
      id: fields[0] as String,
      roomId: fields[1] as String,
      senderId: fields[2] as String,
      receiverId: fields[3] as String,
      content: fields[4] as String,
      timestampMs: fields[5] as int,
      isRead: fields[6] as bool? ?? false,
      isDelivered: fields[7] as bool? ?? false,
      isEdited: fields[8] as bool? ?? false,
      productId: fields[9] as String?,
      productName: fields[10] as String?,
      replyTo: fields[11] as String?,
      replyToContent: fields[12] as String?,
      replyToSender: fields[13] as String?,
      messageType: fields[14] as String? ?? 'text',
      isDeletedForEveryone: fields[15] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, CachedMessage obj) {
    writer.writeMap({
      0: obj.id,
      1: obj.roomId,
      2: obj.senderId,
      3: obj.receiverId,
      4: obj.content,
      5: obj.timestampMs,
      6: obj.isRead,
      7: obj.isDelivered,
      8: obj.isEdited,
      9: obj.productId,
      10: obj.productName,
      11: obj.replyTo,
      12: obj.replyToContent,
      13: obj.replyToSender,
      14: obj.messageType,
      15: obj.isDeletedForEveryone,
    });
  }
}
