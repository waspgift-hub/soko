import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'sms_language_preference.dart';

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

  static Future<String> _lang() => SmsLanguagePreference().get();

  // ─── BOOST ──────────────────────────────────────────────
  static Future<void> notifyBoostPaid({
    required String sellerPhone,
    required String amountPaid,
    required String boostExpiryDate,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Boost payment confirmed. Amount: TZS $amountPaid. '
            'Expires: $boostExpiryDate. Thank you for boosting your listing!'
        : 'Soko Vibe: Malipo ya boost yamethibitishwa. Kiasi: TZS $amountPaid. '
            'Itaisha: $boostExpiryDate. Asante kwa kuweka matangazo!';
    await sendSms(phone: sellerPhone, message: msg);
  }

  // ─── ESCROW ─────────────────────────────────────────────
  static Future<void> notifyEscrowReleased({
    required String sellerPhone,
    required String orderId,
    required String grandTotal,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Payment released for order #$orderId. '
            'Amount: TZS $grandTotal. Thank you for your business!'
        : 'Soko Vibe: Malipo yametolewa kwa order #$orderId. '
            'Kiasi: TZS $grandTotal. Asante kwa biashara yako!';
    await sendSms(phone: sellerPhone, message: msg);
  }

  // ─── DISPATCH ───────────────────────────────────────────
  static Future<void> notifyDispatched({
    required String buyerPhone,
    required String orderId,
    required String busName,
    required String plateNumber,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your order #$orderId has been dispatched. '
            'Company: $busName, Plate: $plateNumber. Thank you!'
        : 'Soko Vibe: Mzigo wako wa order #$orderId umesafirishwa. '
            'Kampuni: $busName, Namba: $plateNumber. Asante!';
    await sendSms(phone: buyerPhone, message: msg);
  }

  // ─── ORDER PLACED ───────────────────────────────────────
  static Future<void> notifyOrderPlaced({
    required String buyerPhone,
    required String orderId,
    required String productName,
    required String total,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your order #$orderId has been placed. '
            'Product: $productName. Total: TZS $total. Please wait for seller confirmation.'
        : 'Soko Vibe: Oda yako #$orderId imewekwa. '
            'Bidhaa: $productName. Jumla: TZS $total. Tafadhali subiri muuzaji athibitishe.';
    await sendSms(phone: buyerPhone, message: msg);
  }

  // ─── SHIPPING QUOTE ─────────────────────────────────────
  static Future<void> notifyShippingQuote({
    required String buyerPhone,
    required String orderId,
    required String shippingCost,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: The shipping cost for order #$orderId is TZS $shippingCost. '
            'Open the app to pay now.'
        : 'Soko Vibe: Gharama ya usafirishaji kwa order #$orderId ni TZS $shippingCost. '
            'Ingia app kulipa sasa.';
    await sendSms(phone: buyerPhone, message: msg);
  }

  // ─── ORDER CONFIRMED ────────────────────────────────────
  static Future<void> notifyOrderConfirmed({
    required String buyerPhone,
    required String orderId,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Order #$orderId confirmed! Your item is being prepared. We will notify you when dispatched.'
        : 'Soko Vibe: Oda #$orderId imethibitishwa! Bidhaa yako inatayarishwa. Tutakujulisha ikisafirishwa.';
    await sendSms(phone: buyerPhone, message: msg);
  }

  // ─── DELIVERY CONFIRMED ─────────────────────────────────
  static Future<void> notifyDeliveryConfirmed({
    required String sellerPhone,
    required String orderId,
    required String amount,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Buyer confirmed delivery of order #$orderId. '
            'TZS $amount has been released to your wallet.'
        : 'Soko Vibe: Mnunuzi amethibitisha kupokea oda #$orderId. '
            'TZS $amount zimetolewa kwenye pochi yako.';
    await sendSms(phone: sellerPhone, message: msg);
  }

  // ─── PAYMENT FAILED ─────────────────────────────────────
  static Future<void> notifyPaymentFailed({
    required String buyerPhone,
    required String orderId,
    required String reason,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Payment for order #$orderId failed. Reason: $reason. Open app to try again.'
        : 'Soko Vibe: Malipo ya oda #$orderId yameshindikana. Sababu: $reason. Ingia app ujaribu tena.';
    await sendSms(phone: buyerPhone, message: msg);
  }

  // ─── REFUND ─────────────────────────────────────────────
  static Future<void> notifyRefunded({
    required String buyerPhone,
    required String orderId,
    required String amount,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Refund of TZS $amount for order #$orderId has been processed. Check your account.'
        : 'Soko Vibe: Marejesho ya TZS $amount kwa oda #$orderId yamekamilika. Angalia akaunti yako.';
    await sendSms(phone: buyerPhone, message: msg);
  }

  // ─── KYC APPROVED ───────────────────────────────────────
  static Future<void> notifyKycApproved({
    required String phone,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your KYC verification has been APPROVED! You can now list unlimited products. Thank you!'
        : 'Soko Vibe: KYC yako IMETHIBITISHWA! Sasa unaweza kuuza bidhaa zisizo na kikomo. Asante!';
    await sendSms(phone: phone, message: msg);
  }

  // ─── KYC REJECTED ───────────────────────────────────────
  static Future<void> notifyKycRejected({
    required String phone,
    required String reason,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your KYC verification was REJECTED. Reason: $reason. Please re-submit with correct documents.'
        : 'Soko Vibe: KYC yako IMEREJESHWA. Sababu: $reason. Tafadhali tuma tena kwa hati sahihi.';
    await sendSms(phone: phone, message: msg);
  }

  // ─── RIDE BOOKED ────────────────────────────────────────
  static Future<void> notifyRideBooked({
    required String riderPhone,
    required String pickup,
    required String dropoff,
    required String driverName,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your ride has been booked! From: $pickup. To: $dropoff. Driver: $driverName. Open app to track.'
        : 'Soko Vibe: Safari yako imehifadhiwa! Kutoka: $pickup. Kwenda: $dropoff. Dereva: $driverName. Fungua app kufuatilia.';
    await sendSms(phone: riderPhone, message: msg);
  }

  // ─── RIDE COMPLETED ─────────────────────────────────────
  static Future<void> notifyRideCompleted({
    required String riderPhone,
    required String amount,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your ride is complete. Fare: TZS $amount. Rate your driver in the app.'
        : 'Soko Vibe: Safari yako imekamilika. Nauli: TZS $amount. Mpe alama dereva wako kwenye app.';
    await sendSms(phone: riderPhone, message: msg);
  }

  // ─── WITHDRAWAL ─────────────────────────────────────────
  static Future<void> notifyWithdrawal({
    required String phone,
    required String amount,
    required String status,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Soko Vibe: Your withdrawal of TZS $amount is $status. Check your wallet for details.'
        : 'Soko Vibe: Utoaji wa TZS $amount ni $status. Angalia pochi yako kwa maelezo.';
    await sendSms(phone: phone, message: msg);
  }

  // ─── WELCOME ────────────────────────────────────────────
  static Future<void> notifyWelcome({
    required String phone,
    required String name,
  }) async {
    final isEn = await _lang() == 'en';
    final msg = isEn
        ? 'Welcome to Soko Vibe, $name! Start buying and selling today. Need help? Contact support@soko-vibe.com'
        : 'Karibu Soko Vibe, $name! Anza kununua na kuuza leo. Una tatizo? Wasiliana support@soko-vibe.com';
    await sendSms(phone: phone, message: msg);
  }
}
