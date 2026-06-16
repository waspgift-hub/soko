import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloudinary_service.dart';
import 'secure_storage_service.dart';

class UserProfile {
  final String uid;
  final String displayName;
  final String username;
  final String bio;
  final String phone;
  final String email;
  final String location;
  final String mood;
  final double? latitude;
  final double? longitude;
  final String profileImage;
  final Map<String, String> paymentNumbers;
  final String accountTier;
  final DateTime? premiumUntil;
  final String shopBanner;
  final String shopBannerColor;
  final String shopAccentColor;
  final bool isVerified;

  UserProfile({
    required this.uid,
    this.displayName = '',
    this.username = '',
    this.bio = '',
    this.phone = '',
    this.email = '',
    this.location = '',
    this.mood = '',
    this.latitude,
    this.longitude,
    this.profileImage = '',
    this.paymentNumbers = const {},
    this.accountTier = 'free',
    this.premiumUntil,
    this.shopBanner = '',
    this.shopBannerColor = '',
    this.shopAccentColor = '',
    this.isVerified = false,
  });

  bool get isPaid => accountTier != 'free';
  bool get isPremium => accountTier == 'premium';
  bool get isSilver => accountTier == 'silver';
  bool get isFree => accountTier == 'free';
  bool get isExpired =>
      premiumUntil != null && DateTime.now().isAfter(premiumUntil!);

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    String tier = data['accountTier'] as String? ?? 'free';
    if (tier == 'free' && data['isPremium'] == true) tier = 'premium';

    Timestamp? ts = data['premiumUntil'] as Timestamp?;
    DateTime? until = ts?.toDate();

    return UserProfile(
      uid: uid,
      displayName: data['displayName'] ?? '',
      username: data['username'] ?? '',
      bio: data['bio'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      location: data['location'] ?? '',
      mood: data['mood'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      profileImage: data['profileImage'] ?? '',
      paymentNumbers: Map<String, String>.from(data['paymentNumbers'] ?? {}),
      accountTier: tier,
      premiumUntil: until,
      shopBanner: data['shopBanner'] ?? '',
      shopBannerColor: data['shopBannerColor'] ?? '',
      shopAccentColor: data['shopAccentColor'] ?? '',
      isVerified: data['isVerified'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'username': username,
    'bio': bio,
    'phone': phone,
    'email': email,
    'location': location,
    'mood': mood,
    'latitude': latitude,
    'longitude': longitude,
    'profileImage': profileImage,
    'paymentNumbers': paymentNumbers,
    'accountTier': accountTier,
    'isPremium': isPaid,
    'premiumUntil': premiumUntil != null
        ? Timestamp.fromDate(premiumUntil!)
        : null,
    'shopBanner': shopBanner,
    'shopBannerColor': shopBannerColor,
    'shopAccentColor': shopAccentColor,
    'isVerified': isVerified,
  };
}

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference _profileDoc() =>
      _db.collection('users').doc(_auth.currentUser!.uid);

  Future<UserProfile?> getProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromMap(uid, doc.data()!);
  }

  Stream<UserProfile?> streamProfile(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map(
          (doc) => doc.exists ? UserProfile.fromMap(uid, doc.data()!) : null,
        );
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _db.collection('users').doc(profile.uid).set(profile.toMap());
  }

  Future<String> uploadProfileImage(String filePath) async {
    return CloudinaryService.uploadFromPath(filePath, folder: 'profiles');
  }

  Future<void> updateProfileImage(String url) async {
    await _profileDoc().update({'profileImage': url});
  }

  Future<bool> isCurrentUserPremium() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final tier = data['accountTier'] as String?;
    if (tier != null) return tier == 'premium' || tier == 'silver';
    return data['isPremium'] == true;
  }

  Future<bool> isPremiumUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final tier = data['accountTier'] as String?;
    if (tier != null) return tier == 'premium' || tier == 'silver';
    return data['isPremium'] == true;
  }

  Future<String> getUserTier(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return 'free';
    final data = doc.data()!;
    final tier = data['accountTier'] as String?;
    if (tier != null) return tier;
    return data['isPremium'] == true ? 'premium' : 'free';
  }

  Future<String> getCurrentTier() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'free';
    return getUserTier(uid);
  }

  Future<void> setAccountTier(
    String uid,
    String tier, {
    Duration? subscriptionDuration,
  }) async {
    DateTime? until;
    if (subscriptionDuration != null && tier != 'free') {
      until = DateTime.now().add(subscriptionDuration);
    }
    await _db.collection('users').doc(uid).set({
      'accountTier': tier,
      'isPremium': tier == 'premium' || tier == 'silver',
      if (until != null) 'premiumUntil': Timestamp.fromDate(until),
    }, SetOptions(merge: true));
  }

  Future<void> setPremium(bool value) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final tier = value ? 'premium' : 'free';
    await setAccountTier(uid, tier);
  }

  Future<bool> isTierExpired(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data()!;
    final tier = data['accountTier'] as String? ?? 'free';
    if (tier == 'free') return false;
    final ts = data['premiumUntil'] as Timestamp?;
    if (ts == null) return false;
    return DateTime.now().isAfter(ts.toDate());
  }

  Future<bool> isUsernameTaken(String username, String currentUid) async {
    if (username.trim().isEmpty) return false;
    final snap = await _db
        .collection('users')
        .where('username', isEqualTo: username.trim().toLowerCase())
        .get();
    for (var doc in snap.docs) {
      if (doc.id != currentUid) return true;
    }
    return false;
  }

  Future<int> getUserProductCount(String uid) async {
    final snap = await _db
        .collection('products')
        .where('sellerId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<int> getUserTotalSales(String uid) async {
    final snap = await _db
        .collection('orders')
        .where('sellerId', isEqualTo: uid)
        .where('status', isEqualTo: 'delivered')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final results = <String, UserProfile>{};
    try {
      final nameSnap = await _db
          .collection('users')
          .where('displayName', isGreaterThanOrEqualTo: q)
          .where('displayName', isLessThan: '$q\uf8ff')
          .limit(20)
          .get();
      for (final doc in nameSnap.docs) {
        results[doc.id] = UserProfile.fromMap(doc.id, doc.data());
      }
      final usernameSnap = await _db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: '$q\uf8ff')
          .limit(20)
          .get();
      for (final doc in usernameSnap.docs) {
        results[doc.id] = UserProfile.fromMap(doc.id, doc.data());
      }
    } catch (_) {
      // Fallback: fetch recent users
      final snap = await _db.collection('users').limit(50).get();
      for (final doc in snap.docs) {
        results[doc.id] = UserProfile.fromMap(doc.id, doc.data());
      }
    }
    return results.values.toList();
  }

  Future<void> updateStorefront(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  Future<void> deleteMyAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    final uid = user.uid;

    // ─── 1. Products (with full cleanup via deleteProduct sub) ───
    final products = await _db.collection('products').where('sellerId', isEqualTo: uid).get();
    for (final doc in products.docs) {
      await _deleteProductsSubCollections(doc.reference, doc.id);
      await doc.reference.delete();
    }

    // ─── 2. Orders (seller + buyer) ───
    for (final role in ['sellerId', 'buyerId']) {
      final orders = await _db.collection('orders').where(role, isEqualTo: uid).get();
      for (final doc in orders.docs) {
        await doc.reference.delete();
      }
    }

    // ─── 3. Conversations + their messages ───
    final conversations = await _db.collection('conversations').where('participants', arrayContains: uid).get();
    for (final conv in conversations.docs) {
      final messages = await conv.reference.collection('messages').get();
      if (messages.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final msg in messages.docs) batch.delete(msg.reference);
        await batch.commit();
      }
      await conv.reference.delete();
    }

    // ─── 4. Groups created by user + their messages ───
    final groups = await _db.collection('groups').where('createdBy', isEqualTo: uid).get();
    for (final group in groups.docs) {
      final messages = await group.reference.collection('messages').get();
      if (messages.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final msg in messages.docs) batch.delete(msg.reference);
        await batch.commit();
      }
      await group.reference.delete();
    }

    // ─── 5. Calls ───
    for (final field in ['callerId', 'receiverId']) {
      final calls = await _db.collection('calls').where(field, isEqualTo: uid).get();
      for (final doc in calls.docs) await doc.reference.delete();
    }

    // ─── 6. Reviews by user ───
    final reviews = await _db.collection('reviews').where('userId', isEqualTo: uid).get();
    for (final doc in reviews.docs) await doc.reference.delete();

    // ─── 7. Comments by user on all products ───
    final comments = await _db.collectionGroup('comments').where('userId', isEqualTo: uid).get();
    for (final doc in comments.docs) await doc.reference.delete();

    // ─── 8. Statuses ───
    final statuses = await _db.collection('statuses').where('userId', isEqualTo: uid).get();
    for (final doc in statuses.docs) await doc.reference.delete();

    // ─── 9. Notifications ───
    final notifications = await _db.collection('notifications').where('userId', isEqualTo: uid).get();
    for (final doc in notifications.docs) await doc.reference.delete();

    // ─── 10. Cart items + cart document ───
    final cartItems = await _db.collection('carts').doc(uid).collection('items').get();
    if (cartItems.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in cartItems.docs) batch.delete(doc.reference);
      await batch.commit();
    }
    await _db.collection('carts').doc(uid).delete();

    // ─── 11. Wallet ───
    await _db.collection('wallets').doc(uid).delete();

    // ─── 12. Disputes ───
    final disputes = await _db.collection('disputes').where('buyerId', isEqualTo: uid).get();
    for (final doc in disputes.docs) await doc.reference.delete();

    // ─── 13. Revenue transactions ───
    final revenueTx = await _db.collection('revenue_transactions').where('userId', isEqualTo: uid).get();
    for (final doc in revenueTx.docs) await doc.reference.delete();

    // ─── 14. Blocked records ───
    final blocked = await _db.collection('blocked').where('userId', isEqualTo: uid).get();
    for (final doc in blocked.docs) await doc.reference.delete();

    // ─── 15. Following / Followers ───
    final following = await _db.collection('users').doc(uid).collection('following').get();
    for (final doc in following.docs) await doc.reference.delete();
    final followers = await _db.collection('users').doc(uid).collection('followers').get();
    for (final doc in followers.docs) await doc.reference.delete();

    // ─── 16. User document ───
    await _db.collection('users').doc(uid).delete();

    // ─── 17. Delete Firebase Auth account + sign out ───
    await user.delete();
    await _auth.signOut();

    // ─── 18. Clear local storage ───
    await SecureStorageService.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Helper: delete all subcollections under a product (comments, replies, cart items, flash sales)
  Future<void> _deleteProductsSubCollections(DocumentReference productRef, String productId) async {
    // Comments + replies
    final comments = await productRef.collection('comments').get();
    for (final comment in comments.docs) {
      final replies = await comment.reference.collection('replies').get();
      if (replies.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final reply in replies.docs) batch.delete(reply.reference);
        await batch.commit();
      }
      await comment.reference.delete();
    }

    // Cart items referencing this product
    final cartItems = await _db
        .collectionGroup('items')
        .where(FieldPath.documentId, isEqualTo: productId)
        .get();
    if (cartItems.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final item in cartItems.docs) batch.delete(item.reference);
      await batch.commit();
    }

    // End flash sales
    final flashSales = await _db
        .collection('flash_sales')
        .where('productId', isEqualTo: productId)
        .where('isActive', isEqualTo: true)
        .get();
    for (final sale in flashSales.docs) {
      await sale.reference.update({'status': 'ended', 'isActive': false});
    }
  }

  Future<void> autoDowngradeExpired(String uid) async {
    if (await isTierExpired(uid)) {
      await _db.collection('users').doc(uid).update({
        'accountTier': 'free',
        'isPremium': false,
        'premiumUntil': null,
        'isVerified': false,
      });
    }
  }

  Future<void> setVerified(String uid, bool verified) async {
    await _db.collection('users').doc(uid).update({
      'isVerified': verified,
    });
  }
}
