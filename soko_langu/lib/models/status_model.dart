import 'package:cloud_firestore/cloud_firestore.dart';

class StatusUpdate {
  final String id;
  final String userId;
  final String userName;
  final String? userImage;
  final String type; // 'text', 'image', 'video'
  final String? textContent;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewers;

  const StatusUpdate({
    required this.id,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.type,
    this.textContent,
    this.mediaUrl,
    this.thumbnailUrl,
    required this.createdAt,
    required this.expiresAt,
    this.viewers = const [],
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get hasText => textContent != null && textContent!.isNotEmpty;
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userImage': userImage,
      'type': type,
      'textContent': textContent,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewers': viewers,
    };
  }

  factory StatusUpdate.fromMap(String id, Map<String, dynamic> map) {
    return StatusUpdate(
      id: id,
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String? ?? '',
      userImage: map['userImage'] as String?,
      type: map['type'] as String? ?? 'text',
      textContent: map['textContent'] as String?,
      mediaUrl: map['mediaUrl'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (map['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      viewers: List<String>.from(map['viewers'] ?? []),
    );
  }
}

class StatusViewerState {
  final String userId;
  final String userName;
  final String? userImage;
  final List<StatusUpdate> updates;
  final bool hasUnviewed;

  const StatusViewerState({
    required this.userId,
    required this.userName,
    this.userImage,
    required this.updates,
    required this.hasUnviewed,
  });

  int get totalUpdates => updates.length;
  int get unviewedCount => updates.where((s) => !s.viewers.contains(userId)).length;
}
