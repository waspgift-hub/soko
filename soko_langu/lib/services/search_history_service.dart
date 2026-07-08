import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static const String _key = 'search_history';
  final List<String> _history = [];
  List<String> get history => List.unmodifiable(_history);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_key);
    if (data != null) _history.addAll(data);
  }

  Future<List<String>> getHistory() async => List.unmodifiable(_history);

  Future<void> addQuery(String query) async {
    _history.remove(query);
    _history.insert(0, query);
    if (_history.length > 20) _history.removeLast();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _history);
  }

  Future<void> removeQuery(String query) async {
    _history.remove(query);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _history);
  }

  Future<void> clearAll() async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
