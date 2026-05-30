import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime timestamp;
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
  final Map<String, List<String>> reactions;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
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
    this.reactions = const {},
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final rawReactions = data['reactions'] as Map<String, dynamic>? ?? {};
    final reactions = <String, List<String>>{};
    rawReactions.forEach((key, value) {
      reactions[key] = List<String>.from(value as List);
    });
    return Message(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      content: data['content'] ?? '',
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isRead: data['isRead'] ?? false,
      isDelivered: data['isDelivered'] ?? false,
      isEdited: data['isEdited'] ?? false,
      productId: data['productId'],
      productName: data['productName'],
      replyTo: data['replyTo'],
      replyToContent: data['replyToContent'],
      replyToSender: data['replyToSender'],
      messageType: data['messageType'] ?? 'text',
      isDeletedForEveryone: data['isDeletedForEveryone'] ?? false,
      reactions: reactions,
    );
  }

  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'receiverId': receiverId,
    'content': content,
    'timestamp': FieldValue.serverTimestamp(),
    'isRead': isRead,
    'isDelivered': isDelivered,
    'isEdited': isEdited,
    'productId': productId,
    'productName': productName,
    'replyTo': replyTo,
    'replyToContent': replyToContent,
    'replyToSender': replyToSender,
    'messageType': messageType,
    'isDeletedForEveryone': isDeletedForEveryone,
    'reactions': reactions,
  };

  Message copyWith({
    String? content,
    bool? isRead,
    bool? isDelivered,
    bool? isEdited,
    String? replyTo,
    String? replyToContent,
    String? replyToSender,
    String? messageType,
    bool? isDeletedForEveryone,
    Map<String, List<String>>? reactions,
  }) {
    return Message(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      content: content ?? this.content,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      isEdited: isEdited ?? this.isEdited,
      productId: productId,
      productName: productName,
      replyTo: replyTo ?? this.replyTo,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSender: replyToSender ?? this.replyToSender,
      messageType: messageType ?? this.messageType,
      isDeletedForEveryone: isDeletedForEveryone ?? this.isDeletedForEveryone,
      reactions: reactions ?? this.reactions,
    );
  }
}

class Conversation {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final Map<String, String> participantNames;

  Conversation({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.participantNames = const {},
  });

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: data['lastMessageTime'] is Timestamp
          ? (data['lastMessageTime'] as Timestamp).toDate()
          : DateTime.now(),
      unreadCount: data['unreadCount'] ?? 0,
      isPinned: data['isPinned'] ?? false,
      isMuted: data['isMuted'] ?? false,
      participantNames: Map<String, String>.from(data['participantNames'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
    'participants': participants,
    'lastMessage': lastMessage,
    'lastMessageTime': FieldValue.serverTimestamp(),
    'unreadCount': unreadCount,
    'isPinned': isPinned,
    'isMuted': isMuted,
    'participantNames': participantNames,
  };
}
