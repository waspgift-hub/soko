import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import '../services/fraud_prevention_service.dart';
import '../utils/network_error.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

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
        userMessage: _mapError(e.code),
        originalError: e,
      );
    }
  }

  Future<UserCredential> register({
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
        await _createProfile(user.uid, displayName, email);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Registration failed',
        userMessage: _mapError(e.code),
        originalError: e,
      );
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');
        final result = await _auth.signInWithPopup(provider);
        await _ensureProfileExists(result.user);
        return result;
      }

      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw NetworkError(
          message: 'Google idToken is null',
          userMessage: 'Google Sign-In imeshindwa. Tafadhali jaribu tena.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      await _ensureProfileExists(result.user);
      return result;
    } on NetworkError {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Google Sign-In failed',
        userMessage: _mapError(e.code),
        originalError: e,
      );
    } catch (e) {
      debugPrint('GoogleSignIn error: $e');
      throw NetworkError(
        message: 'Google Sign-In failed: $e',
        userMessage:
            'Google Sign-In imeshindwa. Tafadhali hakikisha umechagua akaunti na jaribu tena.',
      );
    }
  }

  Future<void> logout() async {
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
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

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ---------------------------------------------------------------------------
  // Passwordless Email Auth (Magic Link)
  // ---------------------------------------------------------------------------

  Future<void> sendSignInLink({
    required String email,
    required ActionCodeSettings actionCodeSettings,
  }) async {
    try {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Failed to send magic link',
        userMessage: _mapError(e.code),
        originalError: e,
      );
    }
  }

  static bool isSignInWithEmailLink(String link) {
    return FirebaseAuth.instance.isSignInWithEmailLink(link);
  }

  Future<UserCredential> signInWithEmailLink({
    required String email,
    required String link,
  }) async {
    try {
      final cred = await _auth.signInWithEmailLink(
        email: email,
        emailLink: link,
      );
      await _ensureProfileExists(cred.user);
      return cred;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Failed to sign in with magic link',
        userMessage: _mapError(e.code),
        originalError: e,
      );
    }
  }

  static ActionCodeSettings magicLinkSettings() {
    return ActionCodeSettings(
      url: 'https://sokonimoko-8c171-a8d14.web.app/magic-link',
      handleCodeInApp: true,
      androidPackageName: 'com.sokolangu.app',
      iOSBundleId: 'com.sokolangu.app',
      androidInstallApp: false,
    );
  }

  Future<void> _ensureProfileExists(User? user) async {
    if (user == null) return;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        await _createProfile(
          user.uid,
          user.displayName ?? 'User',
          user.email ?? '',
        );
      }
    } catch (e) {
      debugPrint('ensureProfileExists error: $e');
    }
  }

  Future<void> _createProfile(
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
      debugPrint('createProfile error: $e');
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Hakuna akaunti iliyopatikana kwa barua pepe hii.';
      case 'wrong-password':
        return 'Nenosiri si sahihi. Tafadhali jaribu tena.';
      case 'invalid-email':
        return 'Barua pepe si sahihi.';
      case 'user-disabled':
        return 'Akaunti hii imezimwa. Wasiliana na msaada.';
      case 'email-already-in-use':
        return 'Akaunti yenye barua pepe hii tayari ipo. Jaribu kuingia.';
      case 'weak-password':
        return 'Nenosiri ni fupi sana. Tumia angalau herufi 8.';
      case 'network-request-failed':
        return 'Mtandao dhaifu. Angalia muunganisho wako.';
      case 'too-many-requests':
        return 'Umejaribu mara nyingi sana. Subiri kidogo kisha jaribu tena.';
      case 'invalid-credential':
        return 'Barua pepe au nenosiri si sahihi.';
      case 'account-exists-with-different-credential':
        return 'Akaunti ipo kwa njia tofauti. Jaribu kuingia kwa kutumia Google.';
      case 'requires-recent-login':
        return 'Tafadhali ingia tena kwa usalama kisha jaribu tena.';
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
      case 'provider-already-linked':
        return 'Akaunti hii tayari imeunganishwa na mtandao huu.';
      default:
        return 'Kuna tatizo lililotokea. Tafadhali jaribu tena.';
    }
  }
}
