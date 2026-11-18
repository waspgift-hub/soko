import 'package:cloud_firestore/cloud_firestore.dart';

/// A product comment or a reply to one.
///
/// The backend flattens threads: a reply's [parentId] is always the root
/// comment id, so depth never grows. [replyToId]/[replyToUserName] preserve the
/// "@name" context when replying to another reply.
class ProductComment {
  final String id;
  final String userId;
  final String userName;
  final String username;
  final String? userImage;
  final String text;
  final DateTime createdAt;
  final int replyCount;
  final String? parentId;
  final String? replyToId;
  final String? replyToUserName;
  final bool pinned;
  final DateTime? editedAt;
  final int likeCount;
  final bool likedByMe;
  final List<String> mentions;
  final bool deleted;

  ProductComment({
    required this.id,
    required this.userId,
    required this.userName,
    this.username = '',
    this.userImage,
    required this.text,
    required this.createdAt,
    this.replyCount = 0,
    this.parentId,
    this.replyToId,
    this.replyToUserName,
    this.pinned = false,
    this.editedAt,
    this.likeCount = 0,
    this.likedByMe = false,
    this.mentions = const [],
    this.deleted = false,
  });

  bool get isReply => parentId != null;

  factory ProductComment.fromJson(Map<String, dynamic> json) {
    return ProductComment(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      userName: (json['userName'] ?? 'Unknown').toString(),
      username: (json['username'] ?? '').toString(),
      userImage: json['userImage'] as String?,
      text: (json['text'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
      replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
      parentId: json['parentId'] as String?,
      replyToId: json['replyToId'] as String?,
      replyToUserName: json['replyToUserName'] as String?,
      pinned: json['pinned'] == true,
      editedAt: json['editedAt'] == null ? null : DateTime.tryParse(json['editedAt'].toString()),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] == true,
      mentions: (json['mentions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      deleted: json['deleted'] == true,
    );
  }

  factory ProductComment.fromFirestore(String id, Map<String, dynamic> data) {
    return ProductComment(
      id: id,
      userId: (data['userId'] ?? '').toString(),
      userName: (data['userName'] ?? 'Unknown').toString(),
      username: (data['username'] ?? '').toString(),
      userImage: data['userImage'] as String?,
      text: (data['text'] ?? data['content'] ?? '').toString(),
      createdAt: _asDateTime(data['createdAt']) ?? DateTime.now(),
      replyCount: (data['replyCount'] as num?)?.toInt() ?? 0,
      parentId: data['parentId'] as String?,
      replyToId: data['replyToId'] as String?,
      replyToUserName: data['replyToUserName'] as String?,
      pinned: data['pinned'] == true,
      editedAt: _asDateTime(data['editedAt']),
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: data['likedByMe'] == true,
      mentions: (data['mentions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      deleted: data['deletedAt'] != null,
    );
  }

  /// Accepts a `Timestamp`, `DateTime` or ISO string so the same model works
  /// for the Firestore mirror and for API payloads.
  static DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse(value.toString());
  }

  ProductComment copyWith({
    String? text,
    int? replyCount,
    bool? pinned,
    int? likeCount,
    bool? likedByMe,
    DateTime? editedAt,
    bool? deleted,
  }) {
    return ProductComment(
      id: id,
      userId: userId,
      userName: userName,
      username: username,
      userImage: userImage,
      text: text ?? this.text,
      createdAt: createdAt,
      replyCount: replyCount ?? this.replyCount,
      parentId: parentId,
      replyToId: replyToId,
      replyToUserName: replyToUserName,
      pinned: pinned ?? this.pinned,
      editedAt: editedAt ?? this.editedAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      mentions: mentions,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'username': username,
      'userImage': userImage,
      'text': text,
      'createdAt': createdAt,
      'replyCount': replyCount,
      'parentId': parentId,
      'likeCount': likeCount,
    };
  }
}
