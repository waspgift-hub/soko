class SmsNotificationService {
  SmsNotificationService._();
  static final SmsNotificationService instance = SmsNotificationService._();

  static Future<void> notifyBoostPaid({
    required String sellerPhone,
    required String amountPaid,
    required String boostExpiryDate,
  }) async {
    // stub
  }

  static Future<void> notifyEscrowReleased({
    required String sellerPhone,
    required String orderId,
    required String grandTotal,
  }) async {
    // stub
  }

  static Future<void> notifyDispatched({
    required String buyerPhone,
    required String orderId,
    required String busName,
    required String plateNumber,
  }) async {
    // stub
  }
}
