import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/money_breakdown.dart';
import 'package:soko_vibe/models/transaction_model.dart';

void main() {
  group('getMnoCheckoutFee', () {
    test('returns 0 below the smallest published tier', () {
      // AzamPay's cheapest band starts at 500. Anything under it is not a
      // chargeable checkout, so the fee is zero — previously this fell through to
      // the top band and quoted 7,960 on a 300 TZS purchase.
      expect(getMnoCheckoutFee(0), 0);
      expect(getMnoCheckoutFee(300), 0);
      expect(getMnoCheckoutFee(499), 0);
    });

    test('matches the published AzamPay MNO tiers', () {
      expect(getMnoCheckoutFee(500), 54);
      expect(getMnoCheckoutFee(899), 54);
      expect(getMnoCheckoutFee(900), 92);
      expect(getMnoCheckoutFee(100000), 3240);
      expect(getMnoCheckoutFee(3000000), 7960);
    });

    test('holds at the top band above the published ceiling', () {
      expect(getMnoCheckoutFee(3000001), 7960);
      expect(getMnoCheckoutFee(90000000), 7960);
    });

    test('tier boundaries are contiguous with no gaps', () {
      for (final tier in mnoCheckoutFeeTiers) {
        expect(getMnoCheckoutFee(tier.$1.toDouble()), tier.$3.toDouble());
        expect(getMnoCheckoutFee(tier.$2.toDouble()), tier.$3.toDouble());
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

    test('prefers the AzamPay quoted fee over the local tier table', () {
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

    test('invalid amounts never inherit the top processing band', () {
      expect(getMnoCheckoutFee(double.nan), 0);
      expect(getMnoCheckoutFee(double.infinity), 0);
      expect(getMnoCheckoutFee(double.negativeInfinity), 0);
      expect(getMnoCheckoutFee(-500), 0);
    });

    test('zero commission promotion keeps seller whole and buyer pays fee', () {
      final previous = TransactionFeeBreakdown.platformCommissionPercent;
      TransactionFeeBreakdown.platformCommissionPercent = 0;
      addTearDown(() {
        TransactionFeeBreakdown.platformCommissionPercent = previous;
      });

      final b = TransactionFeeBreakdown(productPrice: 500);
      expect(b.platformFee, 0);
      expect(b.totalAmount, 500);
      expect(b.processingFee, 54);
      expect(b.buyerTotal, 554);
      expect(b.sellerReceives, 500);
      expect(b.sellerNet, 500);
    });

    test('seller-borne fee reduces seller net, not the buyer total', () {
      final b = TransactionFeeBreakdown(
        productPrice: 500,
        quotedProcessingFee: 54,
        processingFeePayer: ProcessingFeePayer.seller,
      );
      expect(b.buyerTotal, 518);
      expect(b.sellerReceives, 500);
      expect(b.sellerNet, 446);
    });

    test('discount lowers both the buyer charge and seller proceeds', () {
      final b = TransactionFeeBreakdown(
        productPrice: 100000,
        discount: 10000,
      );
      expect(b.totalAmount, 103500);
      expect(b.buyerTotal, b.totalAmount - 10000 + b.processingFee);
      expect(b.sellerReceives, 90000);
    });

    test('free delivery is a valid zero shipping quote', () {
      final b = TransactionFeeBreakdown(
        productPrice: 50000,
        shippingCost: 0,
      );
      expect(b.shippingCost, 0);
      expect(b.totalAmount, 51750);
      expect(b.sellerReceives, 50000);
    });
  });
}
