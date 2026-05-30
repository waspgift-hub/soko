import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cloudinary_service.dart';

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

    final batch = _db.batch();

    final products = await _db.collection('products').where('sellerId', isEqualTo: uid).get();
    for (final doc in products.docs) {
      batch.delete(doc.reference);
    }

    final orders = await _db.collection('orders').where('sellerId', isEqualTo: uid).get();
    for (final doc in orders.docs) {
      batch.delete(doc.reference);
    }

    final buyerOrders = await _db.collection('orders').where('buyerId', isEqualTo: uid).get();
    for (final doc in buyerOrders.docs) {
      batch.delete(doc.reference);
    }

    final chats = await _db.collection('chats').where('participants', arrayContains: uid).get();
    for (final doc in chats.docs) {
      batch.delete(doc.reference);
    }

    final calls = await _db.collection('calls').where('callerId', isEqualTo: uid).get();
    for (final doc in calls.docs) {
      batch.delete(doc.reference);
    }
    final callsReceived = await _db.collection('calls').where('receiverId', isEqualTo: uid).get();
    for (final doc in callsReceived.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(_db.collection('users').doc(uid));
    await batch.commit();

    await user.delete();
    await _auth.signOut();
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
