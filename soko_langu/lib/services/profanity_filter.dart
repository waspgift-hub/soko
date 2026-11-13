import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:safe_text/safe_text.dart';
import 'api_config.dart';

class ProfanityFilter {
  static final ProfanityFilter _instance = ProfanityFilter._();
  factory ProfanityFilter() => _instance;
  ProfanityFilter._();

  Future<ProfanityResult> check(String text) async {
    if (text.trim().isEmpty) return ProfanityResult(clean: true);

    final hasBadWord = await SafeTextFilter.containsBadWord(text: text);
    if (!hasBadWord) return ProfanityResult(clean: true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/moderation/check-text'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': text}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return ProfanityResult(
          clean: data['clean'] ?? true,
          banned: data['banned'] ?? false,
          warning: data['warning'],
          message: data['message'],
        );
      }
      return ProfanityResult(clean: false, message: 'Profanity detected');
    } catch (_) {
      return ProfanityResult(clean: false, message: 'Profanity detected');
    }
  }

  String filter(String text) {
    if (text.trim().isEmpty) return text;
    return SafeTextFilter.filterText(text: text);
  }
}

class ProfanityResult {
  final bool clean;
  final bool banned;
  final int? warning;
  final String? message;

  const ProfanityResult({
    required this.clean,
    this.banned = false,
    this.warning,
    this.message,
  });
}
