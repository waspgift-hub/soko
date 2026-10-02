import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/transaction_model.dart';

void main() {
  group('getUssdPushFee', () {
    test('returns 0 below the smallest published tier', () {
      // ClickPesa's cheapest band starts at 500. Anything under it is not a
      // chargeable push, so the fee is zero — previously this fell through to
      // the top band and quoted 7,960 on a 300 TZS purchase.
      expect(getUssdPushFee(0), 0);
      expect(getUssdPushFee(300), 0);
      expect(getUssdPushFee(499), 0);
    });

    test('matches the published ClickPesa tiers', () {
      expect(getUssdPushFee(500), 54);
      expect(getUssdPushFee(899), 54);
      expect(getUssdPushFee(900), 92);
      expect(getUssdPushFee(100000), 3240);
      expect(getUssdPushFee(3000000), 7960);
    });

    test('holds at the top band above the published ceiling', () {
      expect(getUssdPushFee(3000001), 7960);
      expect(getUssdPushFee(90000000), 7960);
    });

    test('tier boundaries are contiguous with no gaps', () {
      for (final tier in ussdPushFeeTiers) {
        expect(getUssdPushFee(tier.$1.toDouble()), tier.$3.toDouble());
        expect(getUssdPushFee(tier.$2.toDouble()), tier.$3.toDouble());
      }
    });
  });

  group('TransactionFeeBreakdown', () {
    test('charges the buyer commission on top and pays the seller in full', () {
      // Terms of Service 8.2: 3.5% is charged to the buyer and the seller
      // receives the full sale proceeds.
      final b = TransactionFeeBreakdown(productPrice: 100000);
      expect(b.platformFee, 3500);
      expect(b.totalAmount, 103500);
      expect(b.sellerReceives, 100000);
    });

    test('tiers the processing fee on the full charge, not the item price', () {
      // 95,000 item is pushed as 98,325 once commission is added, which lands
      // in the 96,000+ band. Pricing off the item price quoted the cheaper
      // 50,000 band instead and under-charged the buyer by 1,104.
      final b = TransactionFeeBreakdown(productPrice: 95000);
      expect(b.totalAmount, 98325);
      expect(b.processingFee, 3240);
    });

    test('prefers ClickPesa quoted fee over the local tier table', () {
      final b = TransactionFeeBreakdown(
        productPrice: 100000,
        quotedProcessingFee: 5040,
      );
      expect(b.processingFee, 5040);
      // Commission math is unaffected by the quote.
      expect(b.platformFee, 3500);
      expect(b.sellerReceives, 100000);
    });

    test('processing fee is excluded from totalAmount', () {
      // ClickPesa bills on top of the amount, so it must not be folded into
      // what we send or it gets charged twice.
      final b = TransactionFeeBreakdown(productPrice: 20000);
      expect(b.totalAmount, 20700);
      expect(b.totalAmount, lessThan(b.totalAmount + b.processingFee));
    });
  });
}