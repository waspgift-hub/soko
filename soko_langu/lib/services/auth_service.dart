import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/network_error.dart';
import 'fraud_prevention_service.dart';

// New locale keys; registered across language maps by the coordinator.
const String _kAuthGoogleFailed = 'auth_google_failed';
const String _kAuthGoogleCancelled = 'auth_google_cancelled';

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
        userMessage: _authError(e.code),
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
        userMessage: _authError(e.code),
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
          userMessage: _kAuthGoogleFailed,
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
          userMessage: _authError(e.code),
          originalError: e,
        );
      }
      debugPrint('GoogleSignIn error: $e');
      throw NetworkError(
        message: 'Google Sign-In failed: $e',
        userMessage: _kAuthGoogleCancelled,
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
      userMessage: 'auth_wrong_phone',
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
        'gender': '',
        'dateOfBirth': '',
        'latitude': null,
        'longitude': null,
        'coins': 0,
        'viewerCoins': 0,
        'soldCount': 0,
        // Trust/financial fields (isAdmin, isSuspended, sellerBalance,
        // walletBalance, ...) are server-owned — rules reject client writes.
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

  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
        return ErrorKeys.noAccount;
      case 'wrong-password':
        return ErrorKeys.wrongPassword;
      case 'invalid-email':
        return ErrorKeys.invalidEmail;
      case 'user-disabled':
        return ErrorKeys.accountDisabled;
      case 'email-already-in-use':
        return ErrorKeys.emailInUse;
      case 'operation-not-allowed':
        return ErrorKeys.operationNotAllowed;
      case 'weak-password':
        return ErrorKeys.weakPassword;
      case 'network-request-failed':
        return ErrorKeys.poorNetwork;
      case 'too-many-requests':
        return ErrorKeys.tooManyAttempts;
      case 'invalid-credential':
        return ErrorKeys.invalidCredentials;
      case 'account-exists-with-different-credential':
        return ErrorKeys.emailInUse;
      case 'requires-recent-login':
        return ErrorKeys.sessionExpired;
      case 'provider-already-linked':
        return ErrorKeys.alreadyExists;
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return 'auth_wrong_phone';
      case 'invalid-verification-code':
        return 'auth_otp_invalid';
      case 'invalid-verification-id':
        return 'auth_otp_expired';
      case 'session-expired':
        return ErrorKeys.sessionExpired;
      case 'quota-exceeded':
        return 'auth_otp_rate_limited';
      case 'credential-already-in-use':
        return ErrorKeys.emailInUse;
      default:
        return ErrorKeys.generic;
    }
  }
}
