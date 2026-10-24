import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/otp_verification_models.dart';

/// State controller for the universal [OtpVerificationScreen].
///
/// Owns the OTP verification lifecycle: send, verify, resend, countdown
/// timers, and error/success states. The controller does not invent a
/// verified state — it only reflects the authoritative [OtpVerificationResult]
/// returned by the caller's verification operation ([OtpVerificationRequest.onVerify]).
class OtpVerificationController extends ChangeNotifier {
  OtpVerificationController({
    required OtpVerificationRequest request,
  }) : _request = request;

  final OtpVerificationRequest _request;

  OtpVerificationRequest get request => _request;

  // Lifecycle state
  OtpVerificationPhase _phase = OtpVerificationPhase.initial;
  OtpVerificationPhase get phase => _phase;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _verifying = false;
  bool get verifying => _verifying;

  bool _sending = false;
  bool get sending => _sending;

  bool _success = false;
  bool get success => _success;

  // Resend countdown
  int _resendLeft = 0;
  int get resendLeft => _resendLeft;
  bool _canResend = false;
  bool get canResend => _canResend;

  // Expiry countdown
  int _expiryLeft = 0;
  int get expiryLeft => _expiryLeft;

  Timer? _resendTimer;
  Timer? _expiryTimer;

  bool _disposed = false;

  static const int _otpExpirySeconds = 300; // 5 minutes — matches Redis TTL

  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  Future<void> initialize() async {
    if (_disposed) return;
    _setPhase(OtpVerificationPhase.initial);
    _startTimers();
    await _sendOtp();
  }

  Future<void> _sendOtp() async {
    if (_request.onResend == null) {
      // No resend callback provided: nothing to send yet, wait for user entry.
      _setPhase(OtpVerificationPhase.sent);
      _startTimers();
      notifyListeners();
      return;
    }
    _setPhase(OtpVerificationPhase.sending);
    final result = await _request.onResend!();
    if (_disposed) return;

    if (result.success) {
      _setPhase(OtpVerificationPhase.sent);
      _startTimers();
    } else {
      _setPhase(OtpVerificationPhase.error);
      _errorMessage = result.userMessage ??
          'Imeshindwa kutuma OTP';
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Verification
  // ------------------------------------------------------------------

  /// Verifies the supplied OTP through the caller's verification operation.
  /// Returns the authoritative result; the caller navigates only on success.
  Future<OtpVerificationResult> verify(String otp) async {
    if (_verifying || _success || _disposed) {
      return const OtpVerificationResult.failure(
        errorCode: 'already_processing',
        userMessage: 'Verification in progress',
      );
    }
    if (otp.length != _request.otpLength) {
      final msg = 'OTP lazima iwe na nambari ${_request.otpLength}';
      _setError(msg);
      return OtpVerificationResult.failure(
        errorCode: 'otp_invalid_length',
        userMessage: msg,
      );
    }

    _setPhase(OtpVerificationPhase.verifying);
    _verifying = true;
    _errorMessage = null;
    notifyListeners();

    final onVerify = _request.onVerify;
    if (onVerify == null) {
      _setPhase(OtpVerificationPhase.error);
      _errorMessage = 'No verification handler configured';
      _verifying = false;
      notifyListeners();
      return const OtpVerificationResult.failure(
        errorCode: 'no_handler',
        userMessage: 'No verification handler configured',
      );
    }

    final result = await onVerify(otp);

    if (_disposed) return result;

    if (result.success) {
      _setPhase(OtpVerificationPhase.verified);
      _success = true;
    } else {
      _setPhase(OtpVerificationPhase.error);
      _errorMessage = result.userMessage ?? 'OTP si sahihi';
    }
    _verifying = false;
    notifyListeners();
    return result;
  }

  // ------------------------------------------------------------------
  // Resend
  // ------------------------------------------------------------------

  Future<void> resend() async {
    if (!_canResend || _sending || _disposed || _request.onResend == null)
      return;
    _sending = true;
    notifyListeners();

    final result = await _request.onResend!();

    if (_disposed) return;

    if (result.success) {
      _startTimers();
      _errorMessage = null;
      _setPhase(OtpVerificationPhase.sent);
    } else {
      _setPhase(OtpVerificationPhase.error);
      _errorMessage = result.userMessage ?? 'Imeshindwa kutuma OTP';
    }
    _sending = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Timers
  // ------------------------------------------------------------------

  void _startTimers() {
    _resendTimer?.cancel();
    _expiryTimer?.cancel();

    _resendLeft = 60;
    _canResend = false;
    _expiryLeft = _otpExpirySeconds;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (_resendLeft > 0) {
        _resendLeft--;
      } else {
        _canResend = true;
        _resendTimer?.cancel();
      }
      notifyListeners();
    });

    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (_expiryLeft > 0) {
        _expiryLeft--;
      } else {
        _expiryTimer?.cancel();
        if (!_success && !_disposed) {
          _setPhase(OtpVerificationPhase.expired);
        }
      }
      notifyListeners();
    });
  }

  void _stopTimers() {
    _resendTimer?.cancel();
    _expiryTimer?.cancel();
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  void _setPhase(OtpVerificationPhase phase) {
    _phase = phase;
  }

  void _setError(String? message) {
    _errorMessage = message;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    super.dispose();
  }
}

/// Lifecycle phases of an OTP verification.
enum OtpVerificationPhase {
  initial,    // waiting for first send
  sending,    // send request in flight
  sent,       // code sent, awaiting entry
  verifying,  // verify request in flight
  verified,   // backend confirmed valid
  error,      // send/verify failure
  expired,    // challenge TTL elapsed without success
}
