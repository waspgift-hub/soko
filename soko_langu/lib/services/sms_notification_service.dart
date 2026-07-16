import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class SmsNotificationService {
  SmsNotificationService._();
  static final SmsNotificationService instance = SmsNotificationService._();

  static Future<bool> sendSms({
    required String phone,
    required String message,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/sms/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'message': message,
        }),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> notifyBoostPaid({
    required String sellerPhone,
    required String amountPaid,
    required String boostExpiryDate,
  }) async {
    final msg = 'Soko Vibe: Malipo ya boost yamethibitishwa. Kiasi: TZS $amountPaid. '
        'Itaisha: $boostExpiryDate. Asante kwa kuweka matangazo!';
    await sendSms(phone: sellerPhone, message: msg);
  }

  static Future<void> notifyEscrowReleased({
    required String sellerPhone,
    required String orderId,
    required String grandTotal,
  }) async {
    final msg = 'Soko Vibe: Malipo yametolewa kwa order #$orderId. '
        'Kiasi: TZS $grandTotal. Asante kwa biashara yako!';
    await sendSms(phone: sellerPhone, message: msg);
  }

  static Future<void> notifyDispatched({
    required String buyerPhone,
    required String orderId,
    required String busName,
    required String plateNumber,
  }) async {
    final msg = 'Soko Vibe: Mzigo wako wa order #$orderId umesafirishwa. '
        'Kampuni: $busName, Namba: $plateNumber. Asante!';
    await sendSms(phone: buyerPhone, message: msg);
  }

  static Future<void> notifyOrderPlaced({
    required String buyerPhone,
    required String orderId,
    required String productName,
    required String total,
  }) async {
    final msg = 'Soko Vibe: Oda yako #$orderId imewekwa. '
        'Bidhaa: $productName. Jumla: TZS $total. Tafadhali subiri muuzaji athibitishe.';
    await sendSms(phone: buyerPhone, message: msg);
  }

  static Future<void> notifyShippingQuote({
    required String buyerPhone,
    required String orderId,
    required String shippingCost,
  }) async {
    final msg = 'Soko Vibe: Gharama ya usafirishaji kwa order #$orderId ni TZS $shippingCost. '
        'Ingia app kulipa sasa.';
    await sendSms(phone: buyerPhone, message: msg);
  }
}
