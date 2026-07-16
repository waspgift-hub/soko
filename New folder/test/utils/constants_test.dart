import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/utils/constants.dart';

void main() {
  group('AppConstants', () {
    test('app name', () {
      expect(AppConstants.appName, 'Soko Vibe');
    });
    test('currency', () {
      expect(AppConstants.currency, 'TZS');
    });
    test('country', () {
      expect(AppConstants.country, 'Tanzania');
    });
    test('boost price and duration', () {
      expect(AppConstants.boostPrice, 500);
      expect(AppConstants.boostDurationHours, 24);
    });
    test('ad revenue constants', () {
      expect(AppConstants.adRevenuePerView, 10);
      expect(AppConstants.sellerAdShare, 0.4);
      expect(AppConstants.platformAdShare, 0.6);
    });
    test('gift share constants', () {
      expect(AppConstants.streamerGiftShare, 0.7);
      expect(AppConstants.platformGiftShare, 0.3);
    });
    test('payout fees', () {
      expect(AppConstants.payoutFee, 4000);
      expect(AppConstants.payoutFeePlatform, 2000);
      expect(AppConstants.payoutFeeMongike, 2000);
    });
    test('coin rate', () {
      expect(AppConstants.coinRate, 5);
    });
    test('coin packages defined', () {
      expect(AppConstants.coinPackages.length, 6);
      expect(AppConstants.coinPackages[0], {'coins': 100, 'price': 500});
      expect(AppConstants.coinPackages[3], {'coins': 1000, 'price': 4000});
      expect(AppConstants.coinPackages[5], {'coins': 5000, 'price': 15000});
    });
  });
}
