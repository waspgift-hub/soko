import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/network_error.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get userStream => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> register(String email, String password) async {
    return guardNetwork(
      () => _auth.createUserWithEmailAndPassword(email: email, password: password),
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

      final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
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
        userMessage: 'Google Sign-In imeshindwa. Tafadhali hakikisha umechagua akaunti na jaribu tena.',
        originalError: e,
      );
    }
  }

  Future<void> resetPassword(String email) async {
    return guardNetwork(() => _auth.sendPasswordResetEmail(email: email));
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
      if (!kIsWeb) {
        await GoogleSignIn.instance.signOut();
      }
      await _auth.signOut();
    } catch (_) {}
  }

  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw NetworkError(
      message: 'No user logged in',
      userMessage: 'Huna akaunti uliyoingia.',
    );
    await _db.collection('users').doc(user.uid).delete();
    await user.delete();
    await _auth.signOut();
  }

  Future<void> _createUserProfile(String uid, String displayName, String email) async {
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
        'accountTier': 'free',
        'isPremium': false,
        'paymentNumbers': {},
        'shopBanner': '',
        'shopBannerColor': '',
        'shopAccentColor': '',
        'latitude': null,
        'longitude': null,
        'premiumUntil': null,
        'coins': 0,
        'viewerCoins': 0,
        'sellerBalance': 0,
        'soldCount': 0,
        'isAdmin': false,
        'isSuspended': false,
        'agoraUid': '',
        'online': false,
        'lastSeen': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
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
        return 'Nenosiri ni fupi sana. Tumia angalau herufi 6 au zaidi.';
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
      default:
        return 'Kuna tatizo lililotokea. Tafadhali jaribu tena.';
    }
  }
}
