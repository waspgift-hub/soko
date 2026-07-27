import 'package:flutter/services.dart';

class WidgetService {
  static const _channel = MethodChannel('soko_lang/widget');

  static Future<void> updateWidget({
    required String sales,
    required String orders,
    required String balance,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'sales': sales,
        'orders': orders,
        'balance': balance,
      });
    } catch (_) {}
  }
}
