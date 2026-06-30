import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/whatsapp_service.dart';

/// Opens WhatsApp chat with the seller directly.
Future<void> showChatOptions({
  required BuildContext context,
  required String sellerId,
  required String sellerName,
  String? phone,
  String? productName,
  double productPrice = 0,
  String? currency,
}) async {
  String? resolvedPhone = phone;
  if (resolvedPhone == null || resolvedPhone.isEmpty) {
    final profile = await UserService().getProfile(sellerId);
    resolvedPhone = profile?.phone;
  }

  if (!context.mounted) return;

  if (resolvedPhone == null || resolvedPhone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No phone number available for $sellerName')),
    );
    return;
  }

  final msg = productName != null
      ? WhatsAppService.generateProductInquiryMessage(
          sellerName: sellerName,
          productName: productName,
          productPrice: productPrice,
          currencySymbol: _currencySymbol(currency ?? 'TZS'),
        )
      : WhatsAppService.generateProfileMessage(sellerName: sellerName);
  WhatsAppService().openWhatsApp(phoneNumber: resolvedPhone, message: msg);
}

String _currencySymbol(String code) {
  switch (code) {
    case 'TZS':
      return 'TSh';
    case 'USD':
      return '\$';
    case 'KES':
      return 'KSh';
    case 'RWF':
      return 'FRw';
    default:
      return code;
  }
}
