import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/network_error.dart';

class LiveStream {
  final String channelName;
  final String userId;
  final String userName;
  final String userTier;
  final String productId;
  final String productName;
  final String? productImage;
  final bool isActive;
  final int viewerCount;
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
    this.viewerCount = 0,
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
      viewerCount: (data['viewerCount'] ?? data['viewers'] ?? 0) as int,
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
    bool isActive = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null)
      throw NetworkError(
        message: 'Not authenticated',
        userMessage: 'Tafadhali ingia kwanza.',
      );

    channelName ??= 'live_${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final tier = userDoc.data()?['accountTier'] as String? ?? 'free';
    await _db.collection('live_streams').doc(channelName).set({
      'userId': user.uid,
      'hostId': user.uid,
      'userName': user.displayName ?? user.email ?? 'Seller',
      'userTier': tier,
      'title': productName,
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'isActive': isActive,
      'active': isActive,
      'viewerCount': 0,
      'viewers': 0,
      'startedAt': FieldValue.serverTimestamp(),
    });

    return channelName;
  }

  Future<void> incrementViewers(String channelName) async {
    await _db.collection('live_streams').doc(channelName).update({
      'viewerCount': FieldValue.increment(1),
      'viewers': FieldValue.increment(1),
    });
  }

  Future<void> decrementViewers(String channelName) async {
    await _db.collection('live_streams').doc(channelName).update({
      'viewerCount': FieldValue.increment(-1),
      'viewers': FieldValue.increment(-1),
    });
  }

  Stream<int> streamViewerCount(String channelName) {
    return _db.collection('live_streams').doc(channelName).snapshots().map((doc) {
      if (!doc.exists) return 0;
      return (doc.data()?['viewerCount'] ?? doc.data()?['viewers'] ?? 0) as int;
    });
  }

  Future<void> activateLive(String channelName) async {
    await _db.collection('live_streams').doc(channelName).update({
      'isActive': true,
    });
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

  Future<void> addViewerReaction(String channelName, String type) async {
    await _db.collection('live_streams').doc(channelName).collection('reactions').add({
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> requestCoHost(String channelName, String viewerId, String viewerName) async {
    await _db.collection('live_streams').doc(channelName).collection('cohost_requests').add({
      'viewerId': viewerId,
      'viewerName': viewerName,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptCoHost(String channelName, String requestId, String viewerId) async {
    await _db.collection('live_streams').doc(channelName).collection('cohost_requests').doc(requestId).update({
      'status': 'accepted',
    });
    await _db.collection('live_streams').doc(channelName).collection('cohosts').doc(viewerId).set({
      'userId': viewerId,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> declineCoHost(String channelName, String requestId) async {
    await _db.collection('live_streams').doc(channelName).collection('cohost_requests').doc(requestId).update({
      'status': 'declined',
    });
  }

  Stream<List<Map<String, dynamic>>> streamCoHostRequests(String channelName) {
    return _db.collection('live_streams').doc(channelName).collection('cohost_requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> streamCoHosts(String channelName) {
    return _db.collection('live_streams').doc(channelName).collection('cohosts')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }
}
