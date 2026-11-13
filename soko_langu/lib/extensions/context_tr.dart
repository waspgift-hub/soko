import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../services/localization_service.dart';
import '../services/exchange_rate_service.dart';
import '../services/error_reporting_service.dart';
import '../utils/network_error.dart';

extension ContextTr on BuildContext {
  /// Resolves a translation key in the app's current language.
  ///
  /// [fallback] is used when the key is missing from every language map. It was
  /// previously discarded (`[String? _]`), which silently broke every call site
  /// that passed one — 282 of them — leaving those strings to render as
  /// `humanizeKey()` output, i.e. English words shown to Swahili speakers.
  String tr(String key, [String? fallback]) {
    final config = AppConfig.of(this);
    return LocalizationService.translate(
      key,
      config.langCode,
      fallback: fallback,
    );
  }

  /// Renders a user-facing error in the app language. [translateError]
  /// produces a translation key, which is resolved here against the app's
  /// current language so Swahili/English each see their own text.
  String trError(dynamic error, {String? feature, String? screen, Map<String, dynamic>? extraData, bool showErrorId = false}) {
    final config = AppConfig.of(this);
    final key = translateError(error);
    // Fire-and-forget error reporting for observability
    String userMsg = LocalizationService.translate(key, config.langCode);
    try {
      _reportError(error, userMsg, feature: feature, screen: screen, extraData: extraData);
    } catch (_) {}
    try {
      final errorId = ErrorReportingService().lastErrorId;
      if (showErrorId && errorId != null && errorId.isNotEmpty) {
        userMsg = LocalizationService.translate('error_occurred_with_id', config.langCode, fallback: '$userMsg\n\nError ID: $errorId');
        userMsg = userMsg.replaceAll('{0}', errorId);
      }
    } catch (_) {}
    return userMsg;
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

  String trErrorWithId(dynamic error, {String? feature, String? screen, Map<String, dynamic>? extraData}) {
    return trError(error, feature: feature, screen: screen, extraData: extraData, showErrorId: true);
  }
}

void _reportError(dynamic error, String userMsg, {String? feature, String? screen, Map<String, dynamic>? extraData}) {
  ErrorReportingService().reportError(
    error: error,
    userMessage: userMsg,
    feature: feature,
    screen: screen,
    extraData: extraData,
  );
}

