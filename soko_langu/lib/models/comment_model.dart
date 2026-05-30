class ProductComment {
  final String id;
  final String userId;
  final String userName;
  final String? userImage;
  final String text;
  final DateTime createdAt;
  final int replyCount;

  ProductComment({
    required this.id,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.text,
    required this.createdAt,
    this.replyCount = 0,
  });

  factory ProductComment.fromFirestore(String id, Map<String, dynamic> data) {
    return ProductComment(
      id: id,
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? 'Unknown',
      userImage: data['userImage'] as String?,
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      replyCount: data['replyCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userImage': userImage,
      'text': text,
      'createdAt': createdAt,
      'replyCount': replyCount,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'userImage': userImage,
      'text': text,
      'createdAt': createdAt,
      'replyCount': replyCount,
    };
  }
}

class CommentReply {
  final String id;
  final String commentId;
  final String userId;
  final String userName;
  final String? userImage;
  final String text;
  final DateTime createdAt;

  CommentReply({
    required this.id,
    required this.commentId,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.text,
    required this.createdAt,
  });

  factory CommentReply.fromFirestore(
    String id,
    String commentId,
    Map<String, dynamic> data,
  ) {
    return CommentReply(
      id: id,
      commentId: commentId,
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? 'Unknown',
      userImage: data['userImage'] as String?,
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'commentId': commentId,
      'userId': userId,
      'userName': userName,
      'userImage': userImage,
      'text': text,
      'createdAt': createdAt,
    };
  }
}
