import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/models/live_gift.dart';

void main() {
  group('LiveGift', () {
    test('regular gifts are defined', () {
      expect(LiveGift.gifts.length, 4);
      expect(LiveGift.gifts[0].id, 'rose');
      expect(LiveGift.gifts[0].coinCost, 10);
      expect(LiveGift.gifts[3].coinCost, 500);
    });

    test('premium gifts are defined', () {
      expect(LiveGift.premiumGifts.length, 4);
      expect(LiveGift.premiumGifts[0].id, 'universe');
      expect(LiveGift.premiumGifts[0].isPremium, true);
      expect(LiveGift.premiumGifts[0].coinCost, 1000);
      expect(LiveGift.premiumGifts[3].coinCost, 10000);
    });

    test('coin rate constants', () {
      expect(LiveGift.tzsPerPremiumCoin, 5);
      expect(LiveGift.tzsPerSoftCoin, 1);
    });

    test('valueInTzs calculates premium coins correctly', () {
      final gift = LiveGift(id: 'test', emoji: '🎁', name: 'Test', coinCost: 100);
      expect(gift.valueInTzs(10, isPremiumCoin: true), 50);
    });

    test('valueInTzs calculates soft coins correctly', () {
      final gift = LiveGift(id: 'test', emoji: '🎁', name: 'Test', coinCost: 100);
      expect(gift.valueInTzs(10), 10);
    });
  });
}
