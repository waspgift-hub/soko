import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/money_breakdown.dart';

void main() {
  group('TZS parsing', () {
    test('collapses invalid and negative values to zero', () {
      expect(toWholeTzs(1500), 1500);
      expect(toWholeTzs(1500.6), 1501);
      expect(toWholeTzs(-5), 0);
      expect(toWholeTzs(double.nan), 0);
      expect(toWholeTzs(double.infinity), 0);
      expect(toWholeTzs(null), 0);
    });

    test('accepts legacy comma-separated string amounts', () {
      expect(tzsFromDynamic('1,500'), 1500);
      expect(tzsFromDynamic('not a number'), 0);
    });
  });

  group('PricingBreakdown', () {
    test('TZS 500 item charges buyer 554 and pays seller 500', () {
      const b = PricingBreakdown(productPrice: 500, processingFee: 54);

      expect(b.gatewayAmount, 500);
      expect(b.buyerTotal, 554);
      expect(b.sellerEntitlement, 500);
      expect(b.sellerNet, 500);
      expect(b.amountDueNow, 554);
      expect(b.isBalanced, isTrue);
    });

    test('fee is tiered on the gateway amount, not the item price', () {
      const b = PricingBreakdown(
        productPrice: 100000,
        shippingCost: 2000,
        commission: 3500,
        processingFee: 3240,
      );

      expect(b.gatewayAmount, 105500);
      expect(b.buyerTotal, 108740);
      expect(b.sellerEntitlement, 102000);
      expect(b.sellerNet, 102000);
    });

    test('seller-borne fee lowers seller net only', () {
      const b = PricingBreakdown(
        productPrice: 100000,
        commission: 3500,
        processingFee: 3240,
        processingFeePayer: ProcessingFeePayer.seller,
      );

      expect(b.gatewayAmount, 103500);
      expect(b.buyerTotal, 103500);
      expect(b.sellerEntitlement, 100000);
      expect(b.sellerNet, 96760);
    });

    test('discount reduces gateway amount and seller proceeds once', () {
      const b = PricingBreakdown(
        productPrice: 100000,
        commission: 3500,
        discount: 10000,
        processingFee: 920,
      );

      expect(b.gatewayAmount, 93500);
      expect(b.buyerTotal, 94420);
      expect(b.sellerEntitlement, 90000);
    });

    test('terminal orders keep history but clear the amount due', () {
      final b = PricingBreakdown.fromOrder({
        'status': 'refunded',
        'productPrice': 500,
        'processingFee': 54,
      });

      expect(b.buyerTotal, 554);
      expect(b.amountDueNow, 0);
      expect(b.terminal, isTrue);
    });

    test('stored server breakdown wins over legacy top-level fields', () {
      final b = PricingBreakdown.fromOrder({
        'productPrice': 999999,
        'platformFee': 9999,
        'processingFee': 9999,
        'status': 'paid',
        'pricingBreakdown': {
          'productPrice': 70000,
          'shippingCost': 0,
          'commission': 2450,
          'processingFee': 920,
          'processingFeePayer': 'seller',
        },
      });

      expect(b.productPrice, 70000);
      expect(b.commission, 2450);
      expect(b.processingFee, 920);
      expect(b.processingFeePayer, ProcessingFeePayer.seller);
      expect(b.buyerTotal, 72450);
      expect(b.sellerNet, 69080);
    });

    test('toMap exposes the same reconciled figures', () {
      const b = PricingBreakdown(
        productPrice: 500,
        processingFee: 54,
      );
      final map = b.toMap();

      expect(map['gatewayAmount'], 500);
      expect(map['buyerTotal'], 554);
      expect(map['sellerNet'], 500);
      expect(map['processingFeePayer'], 'buyer');
    });
  });
}
