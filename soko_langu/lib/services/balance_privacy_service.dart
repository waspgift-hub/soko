import 'package:flutter/foundation.dart';

class BalancePrivacyService extends ChangeNotifier {
  static final BalancePrivacyService _instance = BalancePrivacyService._();
  factory BalancePrivacyService() => _instance;
  BalancePrivacyService._();

  bool _hideBalances = true;

  bool get hideBalances => _hideBalances;

  void toggle() {
    _hideBalances = !_hideBalances;
    notifyListeners();
  }

  void show() {
    if (_hideBalances) toggle();
  }

  void hide() {
    if (!_hideBalances) toggle();
  }

  /// Returns the masked or real amount string.
  String format(String raw) => _hideBalances ? '****' : raw;

  String formatTzs(double amount) =>
      _hideBalances ? 'TZS ****' : 'TZS ${amount.toStringAsFixed(0)}';

  String formatTzsInt(int amount) =>
      _hideBalances ? 'TZS ****' : 'TZS $amount';
}
