import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';

/// How the app is unlocked when it comes back to the foreground.
///
/// PIN-only, or biometric (fingerprint / face) with the PIN as the fallback.
/// Biometric is never the only way in: a user whose fingerprint sensor stops
/// reading, or who is enrolled on someone else's phone, must still reach their
/// account. That is the same rule iOS and Android apply to their own lock
/// screens.
enum AppLockMethod { pin, biometric }

/// Manages app lock when returning from background.
class AppLockService extends ChangeNotifier {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _pinKey = 'app_lock_pin';
  static const _methodKey = 'app_lock_method';

  bool _isLocked = false;
  bool _pinConfigured = false;
  bool _wentToBackground = false;
  AppLockMethod _method = AppLockMethod.pin;
  bool _biometricAvailable = false;

  bool get isLocked => _isLocked && _pinConfigured;
  bool get pinConfigured => _pinConfigured;
  AppLockMethod get method => _method;
  bool get usesBiometric => _method == AppLockMethod.biometric && _biometricAvailable;

  final LocalAuthentication _auth = LocalAuthentication();

  Future<void> load() async {
    _pinConfigured = await isPinSet();
    _method = await _readMethod();
    _biometricAvailable = await _probeBiometrics();
    notifyListeners();
  }

  Future<bool> isPinSet() async {
    final pin = await SecureStorageService.read(_pinKey);
    return pin != null && pin.length >= 4;
  }

  Future<AppLockMethod> _readMethod() async {
    final raw = await SecureStorageService.read(_methodKey);
    return raw == 'biometric' ? AppLockMethod.biometric : AppLockMethod.pin;
  }

  /// Whether this device can actually do biometric auth right now.
  ///
  /// `canCheckBiometrics` is about enrolled fingerprints; `isDeviceSupported`
  /// also covers face unlock. Both matter: a device can have the hardware and no
  /// enrolled fingerprint, which is the normal state on a fresh phone.
  Future<bool> _probeBiometrics() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.canCheckBiometrics;
    } catch (_) {
      // A platform channel failure must not break app start.
      return false;
    }
  }

  /// Human-readable names of the biometrics this device offers, for the prompt.
  Future<List<BiometricType>> enrolledBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  /// Call when the app moves to background — next resume will require unlock.
  void onBackground() {
    if (_pinConfigured) _wentToBackground = true;
  }

  /// Call on resume; locks if a lock is configured and the app was backgrounded.
  Future<void> onResume() async {
    _pinConfigured = await isPinSet();
    if (_pinConfigured && _wentToBackground) {
      _isLocked = true;
      notifyListeners();
    }
    _wentToBackground = false;
  }

  void unlock() {
    _isLocked = false;
    notifyListeners();
  }

  /// Prompts for a fingerprint / face.
  ///
  /// Returns true only on a successful match. Every failure - cancelled,
  /// too many attempts, no hardware, lockout - returns false so the caller falls
  /// back to the PIN pad. The error code is returned for the message, because
  /// "not recognised" and "too many tries, use your PIN" need different words.
  Future<BiometricResult> authenticate() async {
    if (!_biometricAvailable) {
      return const BiometricResult.unavailable();
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Soko Vibe',
        // Stay on biometric rather than silently falling through to the device
        // PIN: the app's own PIN is the fallback, and two PIN prompts in a row
        // is worse than one.
        biometricOnly: true,
        // Keep the prompt alive across a brief interruption (a notification, a
        // phone call) instead of dropping the user back to the lock screen
        // mid-unlock.
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
      if (ok) {
        _isLocked = false;
        notifyListeners();
      }
      return BiometricResult(ok ? BiometricOutcome.success : BiometricOutcome.failed);
    } on LocalAuthException catch (e) {
      // Every outcome except a plain mismatch sends the user to the PIN pad.
      // Re-prompting after a lockout or a cancel just produces a dialog the
      // user already dismissed.
      return BiometricResult(
        switch (e.code) {
          LocalAuthExceptionCode.noCredentialsSet ||
          LocalAuthExceptionCode.noBiometricsEnrolled ||
          LocalAuthExceptionCode.noBiometricHardware ||
          LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
          LocalAuthExceptionCode.uiUnavailable =>
            BiometricOutcome.unavailable,
          LocalAuthExceptionCode.temporaryLockout ||
          LocalAuthExceptionCode.biometricLockout =>
            BiometricOutcome.lockedOut,
          _ => BiometricOutcome.failed,
        },
        message: e.description,
      );
    } catch (_) {
      return const BiometricResult(BiometricOutcome.failed);
    }
  }

  Future<void> setMethod(AppLockMethod method) async {
    _method = method;
    await SecureStorageService.write(_methodKey, method.name);
    notifyListeners();
  }

  Future<void> clearPin() async {
    await SecureStorageService.delete(_pinKey);
    await SecureStorageService.delete(_methodKey);
    _pinConfigured = false;
    _isLocked = false;
    _wentToBackground = false;
    _method = AppLockMethod.pin;
    notifyListeners();
  }

  Future<void> onPinSaved() async {
    _pinConfigured = true;
    _isLocked = false;
    _wentToBackground = false;
    _biometricAvailable = await _probeBiometrics();
    notifyListeners();
  }
}

/// Why a biometric attempt ended. Modelled as a type rather than a bool so the
/// lock screen can say something useful instead of a generic failure.
enum BiometricOutcome { success, failed, unavailable, lockedOut }

class BiometricResult {
  final BiometricOutcome outcome;
  final String? message;

  const BiometricResult(this.outcome, {this.message});

  const BiometricResult.unavailable() : outcome = BiometricOutcome.unavailable, message = null;

  bool get ok => outcome == BiometricOutcome.success;

  /// True when retrying the prompt is pointless, so the UI should go straight to
  /// the PIN pad instead of re-prompting.
  bool get shouldFallBackToPin =>
      outcome != BiometricOutcome.success;
}
