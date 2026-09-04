import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';
import '../services/fraud_prevention_service.dart';
import '../utils/network_error.dart';
import '../utils/phone_utils.dart';

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

  Future<UserCredential> loginWithPhone(String phone, String otp) async {
    try {
      final normalized = PhoneUtils.toE164(phone);

      final res = await http.post(
        Uri.parse(ApiConfig.v1('/auth/phone-login')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': normalized, 'otp': otp}),
      );

      final body = jsonDecode(res.body);
      if (res.statusCode != 200 || body['success'] != true) {
        throw NetworkError(
          message: 'Phone login failed: ${body['error']}',
          userMessage: body['error'] ?? 'auth_no_account',
        );
      }

      final cred = await _auth.signInWithCustomToken(body['token'] as String);
      await _ensureProfileExists(cred.user);
      return cred;
    } on NetworkError {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Phone login failed',
        userMessage: _mapError(e.code),
        originalError: e,
      );
    } catch (e) {
      throw NetworkError(
        message: 'Phone login error: $e',
        userMessage: ErrorKeys.poorNetwork,
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

  static String phoneToEmail(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    return 'phone_$clean@soko-vibe.com';
  }

  Future<UserCredential> registerWithPhone({
    required String phone,
    required String password,
    required String displayName,
  }) async {
    try {
      final email = phoneToEmail(phone);
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await _createProfile(user.uid, displayName, email,
            phone: phone);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw NetworkError(
        message: e.message ?? 'Phone registration failed',
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
          userMessage: 'auth_google_failed',
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
        userMessage: 'auth_google_cancelled',
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
    String email, {
    String phone = '',
  }) async {
    try {
      await _db.collection('users').doc(uid).set({
        'displayName': displayName,
        'email': email,
        'username': '',
        'bio': '',
        'phone': phone,
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
        'soldCount': 0,
        // Trust/financial fields (isAdmin, isSuspended, sellerBalance,
        // walletBalance, ...) are intentionally NOT written by the client —
        // Firestore rules reject them and the server owns them via Admin SDK.
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
        return ErrorKeys.noAccount;
      case 'wrong-password':
        return ErrorKeys.wrongPassword;
      case 'invalid-email':
        return ErrorKeys.invalidEmail;
      case 'user-disabled':
        return ErrorKeys.accountDisabled;
      case 'email-already-in-use':
        return ErrorKeys.emailInUse;
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
      case 'provider-already-linked':
        return ErrorKeys.alreadyExists;
      default:
        return ErrorKeys.generic;
    }
  }
}
