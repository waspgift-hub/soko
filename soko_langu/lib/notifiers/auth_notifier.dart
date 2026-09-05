import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../repositories/auth_repository.dart';
import '../services/api_config.dart';
import '../services/meseji_service.dart';
import '../services/localization_service.dart';
import '../services/onboarding_service.dart';
import '../utils/network_error.dart';
import '../app/app_state.dart' as app_state;
import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthStatus {
  loading,
  unauthenticated,
  authenticated,
}

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

  bool _isSuspended = false;
  bool get isSuspended => _isSuspended;

  bool _needsProfileSetup = false;
  bool get needsProfileSetup => _needsProfileSetup;

  String? _error;
  String? get error => _error;

  StreamSubscription<User?>? _authSub;

  Future<void> _fetchAdminStatus() async {
    try {
      final user = _authRepo.currentUser;
      if (user == null) { _isAdmin = false; return; }
      // Admin is granted ONLY by the server via the isAdmin flag on the users
      // document (set through /api/setup-admin or the admin SDK). Never derive
      // admin from the email address — anyone can register any email.
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      _isAdmin = data?['isAdmin'] == true;
    } catch (e) {
      debugPrint('[AUTH] Failed to fetch admin status: $e');
      _isAdmin = false;
    }
  }

  Future<void> _checkProfileCompleteness() async {
    try {
      final user = _authRepo.currentUser;
      if (user == null) { _needsProfileSetup = false; return; }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) { _needsProfileSetup = true; return; }
      final data = doc.data()!;
      final hasGender = (data['gender'] as String?)?.isNotEmpty == true;
      final hasDob = (data['dateOfBirth'] as String?)?.isNotEmpty == true;
      final hasLocation = (data['location'] as String?)?.isNotEmpty == true;
      _needsProfileSetup = !(hasGender && hasDob && hasLocation);
    } catch (_) {
      _needsProfileSetup = false;
    }
  }

  Future<void> _checkSuspended() async {
    try {
      final user = _authRepo.currentUser;
      if (user == null) { _isSuspended = false; return; }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      _isSuspended = doc.data()?['isSuspended'] == true;
    } catch (_) {
      _isSuspended = false;
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
      final currentUser = _authRepo.currentUser;

      if (currentUser != null) {
        await _onboardingService.markCompleted();
      }

      if (currentUser != null) {
        _user = currentUser;
        _status = AuthStatus.authenticated;
        await _fetchAdminStatus();
        await _checkSuspended();
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
        if (user != null) {
          _status = AuthStatus.authenticated;
          await _fetchAdminStatus();
          await _checkSuspended();
        } else {
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
      await _checkSuspended();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = translateError(e);
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
      await _checkSuspended();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = translateError(e);
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
      await _checkSuspended();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = translateError(e);
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
      _error = translateError(e);
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
        Uri.parse(ApiConfig.v1('/auth/verify-otp')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['valid'] == true) {
        _phoneOtpState = PhoneOtpState.verified;
        notifyListeners();
        return true;
      } else {
        _error = body['error'] ?? 'auth_otp_invalid';
        _phoneOtpState = PhoneOtpState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = translateError(e);
      _phoneOtpState = PhoneOtpState.error;
      notifyListeners();
      return false;
    }
  }

  /// Returns whether an account already exists for [phone]. Re-throws on
  /// network/server errors so callers decide how to surface them.
  Future<bool> checkPhoneExists(String phone) async {
    final res = await http.post(
      Uri.parse(ApiConfig.v1('/auth/check-phone')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    final body = jsonDecode(res.body);
    return body['exists'] == true;
  }

  /// Returns whether an account already exists for [email]. Re-throws on
  /// network/server errors so callers decide how to surface them.
  Future<bool> checkEmailExists(String email) async {
    if (email.trim().isEmpty) return false;
    final res = await http.post(
      Uri.parse(ApiConfig.v1('/auth/check-email')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    final body = jsonDecode(res.body);
    return body['exists'] == true;
  }

  Future<void> loginWithPhone(String phone, String otp) async {
    _error = null;
    notifyListeners();
    try {
      await _authRepo.loginWithPhone(phone, otp);
      await _onboardingService.markCompleted();
      _setAuthState(_authRepo.currentUser);
      await _fetchAdminStatus();
      await _checkSuspended();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = translateError(e);
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
      await _checkSuspended();
      await _checkProfileCompleteness();
      _syncAppState();
      notifyListeners();
    } catch (e) {
      _error = translateError(e);
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
        Uri.parse(ApiConfig.v1('/auth/send-email-otp')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'langCode': await LocalizationService().getLanguage(),
        }),
      );
      if (res.statusCode == 200) {
        _emailOtpState = EmailOtpState.sent;
      } else {
        final body = jsonDecode(res.body);
        _error = body['error'] ?? 'auth_otp_send_failed';
        _emailOtpState = EmailOtpState.error;
      }
      notifyListeners();
    } catch (e) {
      _error = translateError(e);
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
        Uri.parse(ApiConfig.v1('/auth/verify-email-otp')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['valid'] == true) {
        _emailOtpState = EmailOtpState.verified;
        notifyListeners();
        return true;
      } else {
        _error = body['error'] ?? 'auth_otp_invalid';
        _emailOtpState = EmailOtpState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = translateError(e);
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
  // Shared
  // ---------------------------------------------------------------------------

  Future<void> logout() async {
    await _authRepo.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _isAdmin = false;
    _isSuspended = false;
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
