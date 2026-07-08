import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExchangeRateService {
  static final ExchangeRateService _instance = ExchangeRateService._internal();
  factory ExchangeRateService() => _instance;
  ExchangeRateService._internal();

  Map<String, double>? _rates;
  DateTime? _lastFetch;

  static const String _ratesKey = 'cached_exchange_rates';
  static const String _lastFetchKey = 'cached_exchange_rates_time';
  static const Duration _cacheDuration = Duration(minutes: 15);

  bool get isReady => _rates != null;

  Future<void> initialize() async {
    await _loadCachedRates();
    if (_rates == null || _isStale()) {
      await _fetchRates();
    }
  }

  Future<void> refresh() async {
    await _fetchRates();
  }

  double convert(double priceInTzs, String toCurrency) {
    if (toCurrency == 'TZS' || _rates == null) return priceInTzs;
    final rate = _rates![toCurrency];
    if (rate == null) return priceInTzs;
    return priceInTzs * rate;
  }

  bool _isStale() {
    if (_lastFetch == null) return true;
    return DateTime.now().difference(_lastFetch!) > _cacheDuration;
  }

  Future<void> _loadCachedRates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_ratesKey);
      final time = prefs.getInt(_lastFetchKey);
      if (raw != null && time != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _rates = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
        _lastFetch = DateTime.fromMillisecondsSinceEpoch(time);
      }
    } catch (_) {
      _rates = null;
      _lastFetch = null;
    }
  }

  Future<void> _saveRates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ratesKey, jsonEncode(_rates));
      await prefs.setInt(_lastFetchKey, _lastFetch!.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> _fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.exchangerate-api.com/v4/latest/TZS'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rates = data['rates'] as Map<String, dynamic>;
        _rates = rates.map((k, v) => MapEntry(k, (v as num).toDouble()));
        _lastFetch = DateTime.now();
        await _saveRates();
        debugPrint('ExchangeRateService: rates updated (${_rates!.length} currencies)');
      }
    } catch (e) {
      debugPrint('ExchangeRateService: fetch failed — $e');
      if (_rates == null) {
        _rates = {};
        _lastFetch = DateTime.now();
      }
    }
  }
}
