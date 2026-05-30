import 'package:flutter/material.dart';
import '../main.dart';
import '../services/localization_service.dart';

extension ContextTr on BuildContext {
  String tr(String key) {
    final config = AppConfig.of(this);
    return LocalizationService.translate(key, config.langCode);
  }

  String currencySymbol() {
    final config = AppConfig.of(this);
    return LocalizationService.supportedCurrencies[config.currencyCode]?['symbol'] ?? 'TSh';
  }
}
