import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class AccountTierService {
  static const _key = 'account_tier';
  static final _controller = StreamController<String>.broadcast();

  /// Stream that emits the new tier whenever [setTier] is called.
  Stream<String> get onTierChanged => _controller.stream;

  Future<String> getTier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? 'both';
  }

  Future<bool> get canBuy async => (await getTier()) != 'seller';

  Future<bool> get canSell async => (await getTier()) != 'buyer';

  /// Persists [tier] and notifies listeners via [onTierChanged].
  Future<void> setTier(String tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, tier);
    _controller.add(tier);
  }
}
