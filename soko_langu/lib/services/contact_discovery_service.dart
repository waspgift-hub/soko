import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Client for optional, revocable contact discovery.
///
/// The app never uploads an address book. Opt-in only registers a server
/// HMAC of the signed-in user's own verified phone so matching can happen
/// without storing raw numbers on the client index.
class ContactDiscoveryService {
  static const _base = '${ApiConfig.baseUrl}/api/v1/users/contact-discovery';

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<bool> isOptedIn() async {
    final headers = await _headers();
    final response = await http.get(Uri.parse('$_base/status'), headers: headers);
    if (response.statusCode >= 400) return false;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['enabled'] == true;
  }

  Future<void> optIn({required String ownPhone}) async {
    final headers = await _headers();
    final response = await http.post(
      Uri.parse('$_base/opt-in'),
      headers: headers,
      body: jsonEncode({'phone': ownPhone}),
    );
    if (response.statusCode >= 400) {
      throw StateError('contact_discovery_opt_in_failed');
    }
  }

  Future<void> optOut() async {
    final headers = await _headers();
    final response = await http.post(
      Uri.parse('$_base/opt-out'),
      headers: headers,
      body: jsonEncode({}),
    );
    if (response.statusCode >= 400) {
      throw StateError('contact_discovery_opt_out_failed');
    }
  }
}
