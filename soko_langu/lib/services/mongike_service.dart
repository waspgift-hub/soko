class MongikeService {
  MongikeService._();
  static final MongikeService instance = MongikeService._();

  static Future<Map<String, dynamic>> initiateMarketplacePayment({
    required double productPrice,
    String? productName,
    String? productId,
    String? sellerId,
    String? sellerName,
    String? email,
    required String phone,
    String? buyerId,
    String? deliveryType,
    double? shippingCost,
    String? existingTransactionId,
    String? description,
  }) async {
    return {'success': true, 'order_id': 'mock_order_123'};
  }

  static Future<Map<String, dynamic>> adminWithdraw({
    required double amount,
    required String phone,
    String? userId,
  }) async {
    return {'success': true, 'message': 'Withdrawal initiated'};
  }

  static Future<Map<String, dynamic>> sellerWithdraw({
    required double amount,
    required String phone,
    String? userId,
  }) async {
    return {'success': true, 'message': 'Withdrawal initiated'};
  }

  static Future<bool> verifyPayment(String reference) async {
    return true;
  }
}
