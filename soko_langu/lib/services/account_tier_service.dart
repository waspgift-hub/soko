import 'package:shared_preferences/shared_preferences.dart';

class AccountTierService {
  static const _key = 'account_tier';

  Future<String> getTier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? 'both';
  }

  Future<bool> get canBuy async => (await getTier()) != 'seller';

  Future<bool> get canSell async => (await getTier()) != 'buyer';
}
