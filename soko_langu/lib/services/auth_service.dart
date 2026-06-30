import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/network_error.dart';
import 'fraud_prevention_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get userStream => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> register(String email, String password) async {
    return guardNetwork(
      () => _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  Future<UserCredential> registerWithProfile({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await _createUserProfile(user.uid, displayName, email);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Registration failed',
        userMessage: _swahiliAuthError(e.code),
        originalError: e,
      );
    }
  }

  Future<UserCredential> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _ensureProfileExists(cred.user);
      return cred;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Login failed',
        userMessage: _swahiliAuthError(e.code),
        originalError: e,
      );
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');
        final result = await _auth.signInWithPopup(provider);
        await _ensureProfileExists(result.user);
        return result;
      }

      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw NetworkError(
          message: 'Google idToken is null',
          userMessage: 'Google Sign-In imeshindwa. Tafadhali jaribu tena.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final result = await guardNetwork(
        () => _auth.signInWithCredential(credential),
      );
      await _ensureProfileExists(result.user);
      return result;
    } catch (e) {
      if (e is NetworkError) rethrow;
      if (e is FirebaseAuthException) {
        throw NetworkError(
          message: e.message ?? 'Google Sign-In failed',
          userMessage: _swahiliAuthError(e.code),
          originalError: e,
        );
      }
      debugPrint('GoogleSignIn error: $e');
      throw NetworkError(
        message: 'Google Sign-In failed: $e',
        userMessage:
            'Google Sign-In imeshindwa. Tafadhali hakikisha umechagua akaunti na jaribu tena.',
        originalError: e,
      );
    }
  }

  Future<void> resetPassword(String email) async {
    return guardNetwork(() => _auth.sendPasswordResetEmail(email: email));
  }

  /// Normalizes Tanzanian numbers to E.164 (+2557XXXXXXXX).
  String normalizePhoneToE164(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('255')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length == 9 &&
        (digits.startsWith('6') || digits.startsWith('7'))) {
      return '+255$digits';
    }
    if (input.trim().startsWith('+') && digits.length >= 12) {
      return '+$digits';
    }
    throw NetworkError(
      message: 'Invalid phone',
      userMessage: 'Weka namba sahihi ya Tanzania (mfano 0712345678).',
    );
  }

  List<String> phoneLookupVariants(String input) {
    final variants = <String>{};
    try {
      final e164 = normalizePhoneToE164(input);
      variants.add(e164);
      variants.add(e164.replaceFirst('+255', '0'));
      variants.add(e164.replaceFirst('+', ''));
    } catch (_) {
      variants.add(input.trim());
    }
    return variants.toList();
  }

  Future<Map<String, dynamic>?> findUserProfileByPhone(String phone) async {
    for (final variant in phoneLookupVariants(phone)) {
      if (variant.isEmpty) continue;
      try {
        final snap = await _db
            .collection('users')
            .where('phone', isEqualTo: variant)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final doc = snap.docs.first;
          return {'uid': doc.id, ...doc.data()};
        }
      } catch (e) {
        debugPrint('findUserProfileByPhone: $e');
      }
    }
    return null;
  }

  Future<void> syncPhoneOnProfile(String uid, String phoneE164) async {
    try {
      await _db.collection('users').doc(uid).set({
        'phone': phoneE164.replaceFirst('+255', '0'),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('syncPhoneOnProfile: $e');
    }
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await guardNetwork(() => user.sendEmailVerification());
    }
  }

  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Clean up FCM token
        try {
          await _db.collection('users').doc(user.uid).update({
            'fcmToken': FieldValue.delete(),
          });
        } catch (_) {}
        // Delete all user's notifications
        try {
          final notifs = await _db
              .collection('notifications')
              .where('userId', isEqualTo: user.uid)
              .get();
          final batch = _db.batch();
          for (final doc in notifs.docs) {
            batch.delete(doc.reference);
          }
          if (notifs.docs.isNotEmpty) await batch.commit();
        } catch (_) {}
      }
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }
      await _auth.signOut();
    } catch (_) {}
  }

  Future<void> _createUserProfile(
    String uid,
    String displayName,
    String email,
  ) async {
    try {
      await _db.collection('users').doc(uid).set({
        'displayName': displayName,
        'email': email,
        'username': '',
        'bio': '',
        'phone': '',
        'location': '',
        'mood': '',
        'profileImage': '',
        'paymentNumbers': {},
        'shopBanner': '',
        'shopBannerColor': '',
        'shopAccentColor': '',
        'latitude': null,
        'longitude': null,
        'coins': 0,
        'viewerCoins': 0,
        'sellerBalance': 0,
        'soldCount': 0,
        'isAdmin': false,
        'isSuspended': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await FraudPreventionService().checkNewSeller(uid, displayName);
    } catch (e) {
      debugPrint('createUserProfile error: $e');
    }
  }

  Future<void> _ensureProfileExists(User? user) async {
    if (user == null) return;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        await _createUserProfile(
          user.uid,
          user.displayName ?? 'User',
          user.email ?? '',
        );
      }
    } catch (e) {
      debugPrint('ensureProfileExists error: $e');
    }
  }

  String _swahiliAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Hakuna akaunti iliyopatikana kwa barua pepe hii.';
      case 'wrong-password':
        return 'Nenosiri si sahihi. Tafadhali jaribu tena.';
      case 'invalid-email':
        return 'Barua pepe si sahihi. Tafadhali ingiza barua pepe sahihi.';
      case 'user-disabled':
        return 'Akaunti hii imezimwa. Wasiliana na msaada.';
      case 'email-already-in-use':
        return 'Akaunti yenye barua pepe hii tayari ipo. Jaribu kuingia au tumia barua pepe nyingine.';
      case 'operation-not-allowed':
        return 'Njia hii ya kuingia haijawashwa. Jaribu tena baadaye.';
      case 'weak-password':
        return 'Nenosiri ni fupi sana. Tumia angalau herufi 8 au zaidi.';
      case 'network-request-failed':
        return 'Mtandao dhaifu. Tafadhali angalia muunganisho wako wa intaneti.';
      case 'too-many-requests':
        return 'Umejaribu mara nyingi sana. Tafadhali subiri kidogo kisha jaribu tena.';
      case 'invalid-credential':
        return 'Barua pepe au nenosiri si sahihi. Jaribu "Continue with Google" au uunda akaunti mpya.';
      case 'account-exists-with-different-credential':
        return 'Akaunti ipo kwa njia tofauti. Jaribu kuingia kwa kutumia Google au barua pepe nyingine.';
      case 'requires-recent-login':
        return 'Tafadhali ingia tena kwa usalama kisha jaribu tena.';
      case 'provider-already-linked':
        return 'Akaunti hii tayari imeunganishwa na mtandao huu.';
      case 'invalid-phone-number':
        return 'Namba ya simu si sahihi. Tumia mfano 0712345678.';
      case 'invalid-verification-code':
        return 'OTP si sahihi. Angalia SMS na jaribu tena.';
      case 'invalid-verification-id':
        return 'OTP imeisha muda. Tuma OTP mpya.';
      case 'session-expired':
        return 'Muda wa OTP umeisha. Tuma OTP mpya.';
      case 'quota-exceeded':
        return 'Ujumbe mwingi umetumwa. Subiri kidogo kisha jaribu tena.';
      case 'missing-phone-number':
        return 'Weka namba ya simu.';
      case 'credential-already-in-use':
        return 'Namba hii tayari inatumika na akaunti nyingine.';
      default:
        return 'Kuna tatizo lililotokea. Tafadhali jaribu tena.';
    }
  }
}
