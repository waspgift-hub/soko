import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  static const String _webUrl = 'https://web.whatsapp.com';
  static const String _defaultCountryCode = '255';

  Future<bool> openWhatsApp({
    required String phoneNumber,
    required String message,
    VoidCallback? onError,
    VoidCallback? onFallback,
  }) async {
    try {
      final cleanPhone = _sanitizePhoneNumber(phoneNumber);
      final encodedMessage = Uri.encodeComponent(message);
      
      final whatsappUrl = Uri.parse(
        'https://wa.me/$cleanPhone?text=$encodedMessage',
      );

      if (await canLaunchUrl(whatsappUrl)) {
        final result = await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
        return result;
      } else {
        return await _openWebFallback(message, onFallback);
      }
    } catch (e) {
      debugPrint('WhatsAppService Error: $e');
      onError?.call();
      return false;
    }
  }

  String _sanitizePhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    if (cleaned.startsWith('0')) {
      cleaned = _defaultCountryCode + cleaned.substring(1);
    }
    
    if (!cleaned.startsWith('+')) {
      cleaned = '+$cleaned';
    }
    
    return cleaned.replaceAll('+', '');
  }

  Future<bool> _openWebFallback(String message, VoidCallback? callback) async {
    try {
      final encodedMessage = Uri.encodeComponent(message);
      final webUrl = Uri.parse('$_webUrl/send?text=$encodedMessage');
      
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        callback?.call();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('WhatsApp Web Fallback Error: $e');
      return false;
    }
  }

  static String generateProductInquiryMessage({
    required String sellerName,
    required String productName,
    required double productPrice,
  }) {
    return 'Habari $sellerName, nimeona bidhaa yako "$productName" yenye thamani ya TSh ${productPrice.toStringAsFixed(0)} kwenye app ya Soko Vibe. Naomba kujua zaidi.';
  }

  static String generateProfileInquiryMessage({
    required String sellerName,
  }) {
    return 'Habari $sellerName, nimekuona kwenye app ya Soko Vibe na ningependa kufanya biashara na wewe.';
  }

  static String generateOrderInquiryMessage({
    required String sellerName,
    required String productName,
    required double productPrice,
    required int quantity,
  }) {
    return 'Habari $sellerName, nataka kununua "$productName" (idadi: $quantity) yenye thamani ya TSh ${(productPrice * quantity).toStringAsFixed(0)} kwenye Soko Vibe. Je ipo inapatikana?';
  }
}