import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/auth_repository.dart';
import '../services/api_config.dart';
import '../services/magic_link_service.dart';
import '../services/meseji_service.dart';
import '../services/onboarding_service.dart';
import '../utils/network_error.dart';
import '../app/app_state.dart' as app_state;
import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthStatus {
  loading,
  onboarding,
  unauthenticated,
  authenticated,
}

enum MagicLinkState { idle, sending, sent, error }
enum PhoneOtpState { idle, sending, sent, verifying, verified, error }
enum EmailOtpState { idle, sending, sent, verifying, verified, error }

class AuthNotifier extends ChangeNotifier {
  final AuthRepository _authRepo;
  final OnboardingService _onboardingService;

  AuthNotifier({
    required AuthRepository authRepo,
    required OnboardingService onboardingService,
  })  : _authRepo = authRepo,
        _onboardingService = onboardingService;

  AuthStatus _status = AuthStatus.loading;
  AuthStatus get status => _status;

  User? _user;
  User? get user => _user;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  bool _needsProfileSetup = false;
  bool get needsProfileSetup => _needsProfileSetup;

  String? _error;
  String? get error => _error;

  // Magic Link
  MagicLinkState _magicLinkState = MagicLinkState.idle;
  MagicLinkState get magicLinkState => _magicLinkState;

  String? _magicLinkEmail;
  String? get magicLinkEmail => _magicLinkEmail;

  StreamSubscription<User?>? _authSub;

  Future<void> _fetchAdminStatus() async {
    try {
      final user = _authRepo.currentUser;
      if (user == null) { _isAdmin = false; return; }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      final isAdminEmail = user.email?.toLowerCase() == 'admin@soko-langu.com' ||
          user.email?.toLowerCase() == 'admin@soko-vibe.com';
      _isAdmin = data?['isAdmin'] == true || isAdminEmail;
      // Auto-fix Firestore field for admin emails
      if (isAdminEmail && data?['isAdmin'] != true) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'isAdmin': true},
          SetOptions(merge: true),
        );
      }
      debugPrint('[AUTH] Admin status for ${user.uid}: $_isAdmin');
    } catch (e) {
      debugPrint('[AUTH] Failed to fetch admin status: $e — checking email fallback');
      final user = _authRepo.currentUser;
      _isAdmin = user?.email?.toLowerCase() == 'admin@soko-langu.com' ||
          user?.email?.toLowerCase() == 'admin@soko-vibe.com';
    }
  }

  Future<void> _checkProfileCompleteness() async {
    try {
      final user = _authRepo.currentUser;
      if (user == null) { _needsProfileSetup = false; return; }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) { _needsProfileSetup = true; return; }
      final data = doc.data()!;
      // Skip setup for existing users (profile created >1 hour ago)
      if (data['createdAt'] != null) {
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final isNewUser = DateTime.now().difference(createdAt).inMinutes < 60;
        if (!isNewUser) { _needsProfileSetup = false; return; }
      }
      final hasGender = (data['gender'] as String?)?.isNotEmpty == true;
      final hasDob = (data['dateOfBirth'] as String?)?.isNotEmpty == true;
      final hasLocation = (data['location'] as String?)?.isNotEmpty == true;
      _needsProfileSetup = !(hasGender && hasDob && hasLocation);
    } catch (_) {
      _needsProfileSetup = false;
    }
  }

  Future<void> completeProfileSetup() async {
    _needsProfileSetup = false;
    notifyListeners();
  }

  void _syncAppState() {
    app_state.appStateNotifier.setAuthState(
      authenticated: _status == AuthStatus.authenticated,
      admin: _isAdmin,
    );
  }

  Future<void> initialize() async {
    try {
      final onboardingSeen = await _onboardingService.isCompleted();
      final currentUser = _authRepo.currentUser;

      // User already logged in but onboarding wasn't marked — fix it
      if (!onboardingSeen && currentUser != null) {
        await _onboardingService.markCompleted();
      }

      if (!onboardingSeen && currentUser == null) {
        _status = AuthStatus.onboarding;
        notifyListeners();
        return;
      }

      if (currentUser != null) {
        _user = currentUser;
        _status = AuthStatus.authenticated;
        await _fetchAdminStatus();
        await _checkProfileCompleteness();
      } else {
        _status = AuthStatus.unauthenticated;
      }
      _syncAppState();
      notifyListeners();

      _authSub = _authRepo.authStateChanges.listen((user) async {
        // Skip if already handled in initialize() — prevents re-fetch of admin status
        // that could overwrite with false on transient network errors
        if (_user?.uid == user?.uid && _status == AuthStatus.authenticated) return;
        if (user == null && _status == AuthStatus.unauthenticated) return;

        _user = user;
        if (user != null && _status != AuthStatus.onboarding) {
          _status = AuthStatus.authenticated;
          await _fetchAdminStatus();
        } else if (user == null && _status != AuthStatus.onboarding) {
          _status = AuthStatus.unauthenticated;
          _isAdmin = false;
        }
        _syncAppState();
        notifyListeners();
      });
    } catch (_) {
      _status = AuthStatus.unauthenticated;
      _syncAppState();
      notifyListeners();
    }
  }

  Future<void> completeOnboarding(String? phone) async {
    await _onboardingService.markCompleted();
    if (phone != null && phone.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone_number', phone);
    }

    final currentUser = _authRepo.currentUser;
    _status =
        currentUser != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _setAuthState(User? user) {
    _user = user;
    _status = user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  Future<void> login(String email, String password) async {
    _error = null;
    notifyListeners();
    try {
      await _authRepo.login(email, password);
      await _onboardingService.markCompleted();
      _setAuthState(_authRepo.currentUser);
      await _fetchAdminStatus();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _error = null;
    notifyListeners();
    try {
      await _authRepo.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _onboardingService.markCompleted();
      _setAuthState(_authRepo.currentUser);
      await _fetchAdminStatus();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    _error = null;
    notifyListeners();
    try {
      await _authRepo.signInWithGoogle();
      await _onboardingService.markCompleted();
      _setAuthState(_authRepo.currentUser);
      await _fetchAdminStatus();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Phone OTP
  PhoneOtpState _phoneOtpState = PhoneOtpState.idle;
  PhoneOtpState get phoneOtpState => _phoneOtpState;
  final MesejiService _mesejiService = MesejiService();

  // ---------------------------------------------------------------------------
  // Phone OTP (server-verified — client only triggers send + login)
  // ---------------------------------------------------------------------------

  Future<void> sendPhoneOtp(String phone) async {
    _phoneOtpState = PhoneOtpState.sending;
    _error = null;
    notifyListeners();

    try {
      await _mesejiService.sendOtp(phone);
      _phoneOtpState = PhoneOtpState.sent;
      notifyListeners();
    } catch (e) {
      _error = e is NetworkError ? e.userMessage : 'Imeshindwa kutuma OTP.';
      _phoneOtpState = PhoneOtpState.error;
      notifyListeners();
    }
  }

  /// Server-side OTP verification (used during registration).
  /// Returns true if valid, false otherwise; sets [_error] on failure.
  Future<bool> verifyPhoneOtp(String phone, String otp) async {
    _phoneOtpState = PhoneOtpState.verifying;
    _error = null;
    notifyListeners();

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['valid'] == true) {
        _phoneOtpState = PhoneOtpState.verified;
        notifyListeners();
        return true;
      } else {
        _error = body['error'] ?? 'OTP si sahihi.';
        _phoneOtpState = PhoneOtpState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Mtandao dhaifu. Angalia muunganisho wako.';
      _phoneOtpState = PhoneOtpState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> loginWithPhone(String phone, String otp) async {
    _error = null;
    notifyListeners();
    try {
      await _authRepo.loginWithPhone(phone, otp);
      await _onboardingService.markCompleted();
      _setAuthState(_authRepo.currentUser);
      await _fetchAdminStatus();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = e is NetworkError ? e.userMessage : e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> registerWithPhone({
    required String phone,
    required String password,
    required String displayName,
  }) async {
    _error = null;
    notifyListeners();
    try {
      await _authRepo.registerWithPhone(
        phone: phone,
        password: password,
        displayName: displayName,
      );
      await _onboardingService.markCompleted();
      _setAuthState(_authRepo.currentUser);
      await _fetchAdminStatus();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = e is NetworkError ? e.userMessage : e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void resetPhoneOtp() {
    _phoneOtpState = PhoneOtpState.idle;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Email OTP
  // ---------------------------------------------------------------------------

  EmailOtpState _emailOtpState = EmailOtpState.idle;
  EmailOtpState get emailOtpState => _emailOtpState;

  Future<void> sendEmailOtp(String email) async {
    _emailOtpState = EmailOtpState.sending;
    _error = null;
    notifyListeners();

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/send-email-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (res.statusCode == 200) {
        _emailOtpState = EmailOtpState.sent;
      } else {
        final body = jsonDecode(res.body);
        _error = body['error'] ?? 'Imeshindwa kutuma OTP kwa barua pepe.';
        _emailOtpState = EmailOtpState.error;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Mtandao dhaifu. Angalia muunganisho wako.';
      _emailOtpState = EmailOtpState.error;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailOtp(String email, String otp) async {
    _emailOtpState = EmailOtpState.verifying;
    _error = null;
    notifyListeners();

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-email-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['valid'] == true) {
        _emailOtpState = EmailOtpState.verified;
        notifyListeners();
        return true;
      } else {
        _error = body['error'] ?? 'OTP si sahihi.';
        _emailOtpState = EmailOtpState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Mtandao dhaifu. Angalia muunganisho wako.';
      _emailOtpState = EmailOtpState.error;
      notifyListeners();
      return false;
    }
  }

  void resetEmailOtp() {
    _emailOtpState = EmailOtpState.idle;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Magic Link (Firebase Passwordless Email Auth)
  // ---------------------------------------------------------------------------

  Future<void> sendMagicLink(String email) async {
    _magicLinkState = MagicLinkState.sending;
    _magicLinkEmail = email;
    _error = null;
    notifyListeners();

    try {
      final settings = AuthRepository.magicLinkSettings();
      await _authRepo.sendSignInLink(
        email: email,
        actionCodeSettings: settings,
      );

      await MagicLinkService.saveEmail(email);

      _magicLinkState = MagicLinkState.sent;
      notifyListeners();
    } catch (e) {
      _error = e is NetworkError ? e.userMessage : e.toString();
      _magicLinkState = MagicLinkState.error;
      notifyListeners();
    }
  }

  Future<void> completeMagicLinkSignIn(String email, String link) async {
    _error = null;
    notifyListeners();

    try {
      final cred = await _authRepo.signInWithEmailLink(
        email: email,
        link: link,
      );
      _user = cred.user;
      _status = AuthStatus.authenticated;
      _magicLinkState = MagicLinkState.idle;
      _magicLinkEmail = null;
      await MagicLinkService.clearEmail();
      await _fetchAdminStatus();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = e is NetworkError ? e.userMessage : e.toString();
      _magicLinkState = MagicLinkState.error;
      notifyListeners();
    }
  }

  void resetMagicLink() {
    _magicLinkState = MagicLinkState.idle;
    _magicLinkEmail = null;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Shared
  // ---------------------------------------------------------------------------

  Future<void> logout() async {
    await _authRepo.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _isAdmin = false;
    _needsProfileSetup = false;
    _syncAppState();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
