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

  Future<void> autoDowngradeExpired(String uid) async {
    if (await isTierExpired(uid)) {
      await _db.collection('users').doc(uid).update({
        'accountTier': 'free',
        'isPremium': false,
        'premiumUntil': null,
      });
    }
  }
}
