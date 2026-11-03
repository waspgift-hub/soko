import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
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
  final String gender;
  final String dateOfBirth;
  final DateTime? lastActive;

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
    this.gender = '',
    this.dateOfBirth = '',
    this.lastActive,
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
      gender: data['gender'] ?? '',
      dateOfBirth: data['dateOfBirth'] ?? '',
      lastActive: (data['lastActive'] as dynamic)?.toDate(),
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
    'gender': gender,
    'dateOfBirth': dateOfBirth,
  };

  /// True when no profile content has ever been synced to Postgres (used to
  /// absorb a Firestore-seeded profile over a blank API row).
  bool isEmpty() =>
      displayName.isEmpty &&
      username.isEmpty &&
      email.isEmpty &&
      phone.isEmpty &&
      profileImage.isEmpty;

  /// Returns a profile preferring non-empty values from [other] over this one.
  UserProfile absorb(UserProfile other) {
    String pick(String a, String b) => a.isNotEmpty ? a : b;
    return UserProfile(
      uid: uid,
      displayName: pick(displayName, other.displayName),
      username: pick(username, other.username),
      bio: pick(bio, other.bio),
      phone: pick(phone, other.phone),
      email: pick(email, other.email),
      location: pick(location, other.location),
      mood: pick(mood, other.mood),
      latitude: latitude ?? other.latitude,
      longitude: longitude ?? other.longitude,
      profileImage: pick(profileImage, other.profileImage),
      paymentNumbers:
          paymentNumbers.isEmpty ? other.paymentNumbers : paymentNumbers,
      shopBanner: pick(shopBanner, other.shopBanner),
      shopBannerColor: pick(shopBannerColor, other.shopBannerColor),
      shopAccentColor: pick(shopAccentColor, other.shopAccentColor),
      kycApproved: kycApproved || other.kycApproved,
      gender: pick(gender, other.gender),
      dateOfBirth: pick(dateOfBirth, other.dateOfBirth),
      lastActive: lastActive ?? other.lastActive,
    );
  }
}

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference _profileDoc() =>
      _db.collection('users').doc(_auth.currentUser!.uid);

  Future<UserProfile?> getProfile(String uid) async {
    final self = uid == _auth.currentUser?.uid;
    final api = await _apiProfile(uid, self, await _currentToken());
    if (api != null) {
      // profile_setup/register wrote Firestore directly before the first API
      // save; a blank Postgres row must not blank out an existing profile.
      if (self && api.isEmpty()) {
        final fb = await _db.collection('users').doc(uid).get();
        if (fb.exists) return api.absorb(UserProfile.fromMap(uid, fb.data()!));
      }
      return api;
    }
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromMap(uid, doc.data()!);
  }

  Future<Map<String, UserProfile>> getProfiles(List<String> uids) async {
    if (uids.isEmpty) return {};
    final result = <String, UserProfile>{};
    final missing = <String>[];
    if (ApiConfig.kUseUsersApi) {
      final self = _auth.currentUser?.uid;
      final token = await _currentToken();
      for (final uid in uids) {
        final p = await _apiProfile(uid, uid == self, token);
        if (p != null) {
          result[uid] = p;
        } else {
          missing.add(uid);
        }
      }
    } else {
      missing.addAll(uids);
    }
    final refs = missing.map((id) => _db.collection('users').doc(id)).toList();
    final docs = await Future.wait(refs.map((r) => r.get()));
    for (final doc in docs) {
      if (doc.exists) {
        result[doc.id] = UserProfile.fromMap(doc.id, doc.data()!);
      }
    }
    return result;
  }

  Future<String?> _currentToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<UserProfile?> _apiProfile(String uid, bool self, String? token) async {
    if (!ApiConfig.kUseUsersApi || token == null) return null;
    final path = self ? '/users/me' : '/users/public/$uid';
    try {
      final res = await http.get(
        Uri.parse(ApiConfig.v1(path)),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      final raw = decoded is Map<String, dynamic>
          ? (decoded['data'] is Map<String, dynamic>
              ? decoded['data'] as Map<String, dynamic>
              : decoded)
          : <String, dynamic>{};
      if (raw.isEmpty) return null;
      return _fromApi(uid, raw);
    } catch (_) {
      return null;
    }
  }

  UserProfile _fromApi(String uid, Map<String, dynamic> d) {
    return UserProfile(
      uid: uid,
      displayName: d['displayName'] as String? ?? '',
      username: d['username'] as String? ?? '',
      bio: d['bio'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      email: d['email'] as String? ?? '',
      location: d['location'] as String? ?? '',
      mood: d['mood'] as String? ?? '',
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      profileImage: d['profileImage'] as String? ?? '',
      paymentNumbers: Map<String, String>.from(
        d['paymentNumbers'] is Map<String, dynamic>
            ? d['paymentNumbers'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      shopBanner: d['shopBanner'] as String? ?? '',
      shopBannerColor: d['shopBannerColor'] as String? ?? '',
      shopAccentColor: d['shopAccentColor'] as String? ?? '',
      kycApproved: d['kyc'] is Map<String, dynamic>
          ? d['kyc']['approved'] == true
          : false,
      gender: d['gender'] as String? ?? '',
      dateOfBirth: d['dateOfBirth'] as String? ?? '',
      lastActive: _parseTs(d['lastActive']),
    );
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(
      (v * 1000).round(),
      isUtc: true,
    );
    return null;
  }

  Future<void> _updateSelf(Map<String, dynamic> data) async {
    if (!ApiConfig.kUseUsersApi) return;
    final token = await _currentToken();
    if (token == null) return;
    try {
      await http.put(
        Uri.parse(ApiConfig.v1('/users/me')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );
    } catch (_) {
      // Firestore write below is the source of truth; a failed sync is
      // non-fatal (mirror of the shop adapter rescue pattern).
    }
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
    if (profile.uid == _auth.currentUser?.uid) {
      await _updateSelf(profile.toMap());
    }
    await _db.collection('users').doc(profile.uid).set(profile.toMap(), SetOptions(merge: true));
  }

  /// Persists the user's in-app language to their profile doc so the server
  /// can localize push notifications to match what they chose in the app, and
  /// pings the server so its per-user lang cache applies immediately (instead
  /// of waiting for the 5-minute TTL).
  Future<void> setLanguage(String uid, String langCode) async {
    if (uid.isEmpty) return;
    await _db.collection('users').doc(uid).set({'langCode': langCode}, SetOptions(merge: true));
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      if (token == null) return;
      await http.put(
        Uri.parse(ApiConfig.v1('/users/settings/language_region')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'preferredLanguage': langCode}),
      );
    } catch (_) {
      // Firestore write above is the source of truth; the server cache expires
      // on its own, so a failed sync is non-fatal.
    }
  }

  /// Persists the user's SMS language separately from the in-app language.
  /// SMS going out (OTP, transactional) follows `smsLangCode`; push and
  /// in-app notifications keep following `langCode`.
  Future<void> setSmsLanguage(String uid, String smsLangCode) async {
    if (uid.isEmpty) return;
    await _db
        .collection('users')
        .doc(uid)
        .set({'smsLangCode': smsLangCode}, SetOptions(merge: true));
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      if (token == null) return;
      await http.put(
        Uri.parse(ApiConfig.v1('/users/settings/language_region')),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'smsLangCode': smsLangCode}),
      );
    } catch (_) {
      // Firestore write is the source of truth; the server cache expires on
      // its own, so a failed sync is non-fatal.
    }
  }

  Future<String> uploadProfileImage(String filePath) async {
    return CloudinaryService.uploadFromPath(filePath, folder: 'profiles');
  }

  Future<void> updateProfileImage(String url) async {
    await _updateSelf({'profileImage': url});
    await _profileDoc().update({'profileImage': url});
  }

  /// Deletes the previous profile image from Cloudinary after it has been
  /// replaced. Best-effort: the profile already points at the new image, so a
  /// cleanup failure is swallowed instead of surfacing an error.
  Future<void> deleteProfileImage(String imageUrl) async {
    if (imageUrl.isEmpty || !imageUrl.contains('res.cloudinary.com')) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/cloudinary/delete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'imageUrl': imageUrl}),
      );
    } catch (_) {}
  }

  Future<bool> isUsernameTaken(String username, String currentUid) async {
    if (username.trim().isEmpty) return false;
    if (ApiConfig.kUseUsersApi) {
      final token = await _currentToken();
      if (token != null) {
        try {
          final q = Uri.encodeQueryComponent(username.trim().toLowerCase());
          final res = await http.get(
            Uri.parse(
              ApiConfig.v1(
                '/users/check-username?username=$q&excludeUid=$currentUid',
              ),
            ),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (res.statusCode == 200) {
            final decoded = jsonDecode(res.body);
            final data = decoded['data'];
            if (data is Map<String, dynamic>) {
              return data['available'] == false;
            }
          }
        } catch (_) {}
      }
    }
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
    var q = query.trim().toLowerCase();
    if (q.length > 100) q = q.substring(0, 100);
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
      return [];
    }
    return results.values.toList();
  }

  /// Whitelist of client-writable profile fields. Everything else (trust,
  /// financial, admin state) is server-owned and rejected by Firestore rules.
  static const _storefrontAllowedFields = {
    'displayName', 'username', 'bio', 'location', 'mood',
    'shopBanner', 'shopBannerColor', 'shopAccentColor',
    'profileImage', 'paymentNumbers',
  };

  Future<void> updateStorefront(String uid, Map<String, dynamic> data) async {
    final update = <String, dynamic>{};
    for (final entry in data.entries) {
      if (_storefrontAllowedFields.contains(entry.key)) {
        update[entry.key] = entry.value;
      }
    }
    if (update.isEmpty) return;
    if (uid == _auth.currentUser?.uid) {
      await _updateSelf(update);
    }
    await _db.collection('users').doc(uid).update(update);
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

  /// Update the user's lastActive timestamp for presence.
  Future<void> updateLastActive() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'lastActive': FieldValue.serverTimestamp(),
    });
  }

  /// Persist which chat room the user is currently viewing so the server can
  /// suppress unread counts, pushes, and in-app rows for the live conversation.
  /// null clears the marker.
  Future<void> setActiveChatRoom(String? roomId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      if (roomId == null)
        'activeChatRoom': FieldValue.delete()
      else
        'activeChatRoom': roomId,
    });
  }

  /// Stream the other user's lastActive for presence detection.
  Stream<DateTime?> streamLastActive(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final ts = doc.data()!['lastActive'];
      return (ts as dynamic)?.toDate();
    });
  }

  /// Whether the user is considered online (active within last 2 minutes).
  static bool isOnline(DateTime? lastActive) {
    if (lastActive == null) return false;
    return DateTime.now().difference(lastActive).inMinutes < 2;
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
