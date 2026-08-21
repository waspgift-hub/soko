import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe/services/account_tier_service.dart';

void main() {
  group('AccountTierService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to both when no preference set', () async {
      final service = AccountTierService();
      final tier = await service.getTier();
      expect(tier, 'both');
    });

    test('returns saved buyer tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_tier', 'buyer');
      final service = AccountTierService();
      expect(await service.getTier(), 'buyer');
    });

    test('returns saved seller tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_tier', 'seller');
      final service = AccountTierService();
      expect(await service.getTier(), 'seller');
    });

    test('canBuy is true for buyer tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_tier', 'buyer');
      final service = AccountTierService();
      expect(await service.canBuy, isTrue);
    });

    test('canBuy is false for seller tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_tier', 'seller');
      final service = AccountTierService();
      expect(await service.canBuy, isFalse);
    });

    test('canSell is true for seller tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_tier', 'seller');
      final service = AccountTierService();
      expect(await service.canSell, isTrue);
    });

    test('canSell is false for buyer tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_tier', 'buyer');
      final service = AccountTierService();
      expect(await service.canSell, isFalse);
    });

    test('both tier allows buying and selling', () async {
      final service = AccountTierService();
      expect(await service.getTier(), 'both');
      expect(await service.canBuy, isTrue);
      expect(await service.canSell, isTrue);
    });
  });
}
