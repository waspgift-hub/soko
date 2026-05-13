import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LiveStream {
  final String channelName;
  final String userId;
  final String userName;
  final String userTier;
  final String productId;
  final String productName;
  final String? productImage;
  final bool isActive;
  final DateTime startedAt;

  LiveStream({
    required this.channelName,
    required this.userId,
    required this.userName,
    this.userTier = 'free',
    required this.productId,
    required this.productName,
    this.productImage,
    this.isActive = true,
    required this.startedAt,
  });

  factory LiveStream.fromMap(String id, Map<String, dynamic> data) {
    return LiveStream(
      channelName: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userTier: data['userTier'] as String? ?? 'free',
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      productImage: data['productImage'],
      isActive: data['isActive'] ?? true,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class LiveStreamService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> startLive({
    required String productId,
    required String productName,
    String? productImage,
    String? channelName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    channelName ??= 'live_${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final tier = userDoc.data()?['accountTier'] as String? ?? 'free';
    await _db.collection('live_streams').doc(channelName).set({
      'userId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Seller',
      'userTier': tier,
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'isActive': true,
      'startedAt': FieldValue.serverTimestamp(),
    });

    return channelName;
  }

  Future<void> endLive(String channelName) async {
    await _db.collection('live_streams').doc(channelName).update({
      'isActive': false,
    });
  }

  Stream<List<LiveStream>> getActiveStreams() {
    return _db
        .collection('live_streams')
        .where('isActive', isEqualTo: true)
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => LiveStream.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }
}
