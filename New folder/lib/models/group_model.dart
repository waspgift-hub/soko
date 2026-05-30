import 'package:cloud_firestore/cloud_firestore.dart';

class GroupChat {
  final String id;
  final String name;
  final String imageUrl;
  final String description;
  final List<String> participantIds;
  final List<String> adminIds;
  final String createdBy;
  final DateTime createdAt;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;

  GroupChat({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.description = '',
    required this.participantIds,
    required this.adminIds,
    required this.createdBy,
    required this.createdAt,
    this.lastMessage = '',
    required this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory GroupChat.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return GroupChat(
      id: doc.id,
      name: data['name'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      description: data['description'] ?? '',
      participantIds: List<String>.from(data['participantIds'] ?? []),
      adminIds: List<String>.from(data['adminIds'] ?? []),
      createdBy: data['createdBy'] ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: data['lastMessageTime'] is Timestamp
          ? (data['lastMessageTime'] as Timestamp).toDate()
          : data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      unreadCount: data['unreadCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'imageUrl': imageUrl,
    'description': description,
    'participantIds': participantIds,
    'adminIds': adminIds,
    'createdBy': createdBy,
    'createdAt': FieldValue.serverTimestamp(),
    'lastMessage': lastMessage,
    'lastMessageTime': FieldValue.serverTimestamp(),
    'unreadCount': unreadCount,
  };
}

class GroupMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final String type;
  final bool isSystem;
  final String imageUrl;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.type = 'text',
    this.isSystem = false,
    this.imageUrl = '',
  });

  factory GroupMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return GroupMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      content: data['content'] ?? '',
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      type: data['type'] ?? 'text',
      isSystem: data['isSystem'] == true,
      imageUrl: data['imageUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'senderName': senderName,
    'content': content,
    'timestamp': FieldValue.serverTimestamp(),
    'type': type,
    'isSystem': isSystem,
    'imageUrl': imageUrl,
  };
}
