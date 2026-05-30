import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart' as url_launcher;

class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  static String _sanitizePhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    } else if (cleaned.startsWith('0')) {
      cleaned = '255${cleaned.substring(1)}';
    }
    if (!cleaned.startsWith('255')) {
      cleaned = '255$cleaned';
    }
    return cleaned;
  }

  static String generateProductInquiryMessage({
    required String sellerName,
    required String productName,
    required double productPrice,
    String currencySymbol = 'TSh',
  }) {
    return 'Habari $sellerName, nimeona bidhaa yako "$productName" yenye thamani ya $currencySymbol ${productPrice.toStringAsFixed(0)} kwenye Soko Langu. Naomba kujua zaidi.';
  }

  static String generateProfileMessage({
    required String sellerName,
  }) {
    return 'Habari $sellerName, nimekuona kwenye Soko Langu na ningependa kufanya biashara na wewe.';
  }

  Future<void> openWhatsApp({
    required String phoneNumber,
    required String message,
    void Function()? onError,
    void Function()? onFallback,
  }) async {
    final phone = _sanitizePhone(phoneNumber);
    final encoded = Uri.encodeComponent(message);

    final uri = Uri.parse('whatsapp://send?phone=$phone&text=$encoded');
    final webUri = Uri.parse('https://web.whatsapp.com/send?phone=$phone&text=$encoded');

    try {
      if (await url_launcher.canLaunchUrl(uri)) {
        await url_launcher.launchUrl(uri);
      } else if (await url_launcher.canLaunchUrl(webUri)) {
        await url_launcher.launchUrl(webUri);
        onFallback?.call();
      } else {
        onError?.call();
      }
    } catch (e) {
      if (kIsWeb) {
        onFallback?.call();
      } else {
        onError?.call();
      }
    }
  }
}
