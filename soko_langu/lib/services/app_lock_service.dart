import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

/// Manages PIN-based app lock when returning from background.
class AppLockService extends ChangeNotifier {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  bool _isLocked = false;
  bool _pinConfigured = false;
  bool _wentToBackground = false;

  bool get isLocked => _isLocked && _pinConfigured;
  bool get pinConfigured => _pinConfigured;

  Future<void> load() async {
    _pinConfigured = await isPinSet();
    notifyListeners();
  }

  Future<bool> isPinSet() async {
    final pin = await SecureStorageService.read('app_lock_pin');
    return pin != null && pin.length >= 4;
  }

  /// Call when the app moves to background — next resume will require PIN.
  void onBackground() {
    if (_pinConfigured) _wentToBackground = true;
  }

  /// Call on resume; locks if a PIN is configured and the app was backgrounded.
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

  Future<void> clearPin() async {
    await SecureStorageService.delete('app_lock_pin');
    _pinConfigured = false;
    _isLocked = false;
    _wentToBackground = false;
    notifyListeners();
  }

  Future<void> onPinSaved() async {
    _pinConfigured = true;
    _isLocked = false;
    _wentToBackground = false;
    notifyListeners();
  }
}
