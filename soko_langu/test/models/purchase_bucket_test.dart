import 'package:flutter_test/flutter_test.dart';

import 'package:soko_vibe/models/order_statuses.dart';

void main() {
  test('normalises legacy spellings into the same purchase bucket', () {
    expect(
      purchaseBucketOf('paid_escrow_held'),
      PurchaseBucket.active,
    );
    expect(purchaseBucketOf('paidEscrowHeld'), PurchaseBucket.active);
    expect(purchaseBucketOf('delivery_confirmed'), PurchaseBucket.active);
    expect(purchaseBucketOf('walletCredited'), PurchaseBucket.completed);
  });

  test('separates terminal outcomes from settlement', () {
    expect(purchaseBucketOf('cancelled'), PurchaseBucket.failed);
    expect(purchaseBucketOf('refunded'), PurchaseBucket.failed);
    expect(purchaseBucketOf('disputed'), PurchaseBucket.active);
  });

  test('leaves unknown statuses outside every bucket', () {
    expect(purchaseBucketOf('some-future-status'), isNull);
  });

  test('only lets buyers hide pre-payment and failed orders', () {
    expect(canHidePurchaseFromBuyer('pending'), isTrue);
    expect(canHidePurchaseFromBuyer('payment_failed'), isTrue);
    expect(canHidePurchaseFromBuyer('escrow_hold'), isFalse);
    expect(canHidePurchaseFromBuyer('disputed'), isFalse);
    expect(canHidePurchaseFromBuyer('completed'), isFalse);
  });
}
