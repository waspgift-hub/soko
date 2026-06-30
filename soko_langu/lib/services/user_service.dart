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
  final String shopBanner;
  final String shopBannerColor;
  final String shopAccentColor;
  final bool kycApproved;

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
    this.shopBanner = '',
    this.shopBannerColor = '',
    this.shopAccentColor = '',
    this.kycApproved = false,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
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
      shopBanner: data['shopBanner'] ?? '',
      shopBannerColor: data['shopBannerColor'] ?? '',
      shopAccentColor: data['shopAccentColor'] ?? '',
      kycApproved: data['kyc']?['approved'] ?? false,
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
    'shopBanner': shopBanner,
    'shopBannerColor': shopBannerColor,
    'shopAccentColor': shopAccentColor,
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

    // Reauthenticate is required before deletion on production.
    // Call reauthenticateAndDelete(password) instead.
    if (user.providerData.any((p) => p.providerId == 'password')) {
      throw Exception('reauth_required');
    }
    await _db.collection('users').doc(user.uid).delete();
    await user.delete();
    await _auth.signOut();
  }

  Future<void> reauthenticateAndDelete(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
    await _db.collection('users').doc(user.uid).delete();
    await user.delete();
    await _auth.signOut();
  }
}
