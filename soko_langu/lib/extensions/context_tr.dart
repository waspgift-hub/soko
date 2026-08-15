import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/localization_service.dart';
import '../services/exchange_rate_service.dart';
import '../utils/network_error.dart';

extension ContextTr on BuildContext {
  String tr(String key, [String? _]) {
    final config = AppConfig.of(this);
    return LocalizationService.translate(key, config.langCode);
  }

  /// Renders a user-facing error in the app language. [translateError]
  /// produces a translation key, which is resolved here against the app's
  /// current language so Swahili/English/Chinese each see their own text.
  String trError(dynamic error) {
    final config = AppConfig.of(this);
    final key = translateError(error);
    return LocalizationService.translate(key, config.langCode);
  }

  String trParams(String key, Map<String, String> params) {
    final config = AppConfig.of(this);
    return LocalizationService.trParams(key, config.langCode, params);
  }

  String currencySymbol() {
    final config = AppConfig.of(this);
    return LocalizationService.supportedCurrencies[config.currencyCode]?['symbol'] ?? 'TSh';
  }

  String formatPrice(double price, {String? currencyOverride}) {
    final config = AppConfig.of(this);
    final code = currencyOverride ?? config.currencyCode;
    final symbol = LocalizationService.supportedCurrencies[code]?['symbol'] ?? 'TSh';
    final converted = ExchangeRateService().convert(price, code);
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final formatted = formatter.format(converted);
    return '$symbol $formatted';
  }

  String formatPriceInt(int price, {String? currencyOverride}) {
    final config = AppConfig.of(this);
    final code = currencyOverride ?? config.currencyCode;
    final symbol = LocalizationService.supportedCurrencies[code]?['symbol'] ?? 'TSh';
    final converted = ExchangeRateService().convert(price.toDouble(), code);
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final formatted = formatter.format(converted);
    return '$symbol $formatted';
  }
}
