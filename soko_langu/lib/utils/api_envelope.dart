import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of reading a `{success: ...}` API envelope.
class ApiEnvelope {
  /// True only when the transport succeeded *and* the server said it did.
  ///
  /// HTTP 200 alone is not confirmation: several handlers reply 200 with
  /// `{success: false, error: ...}`, and showing a success toast on those
  /// tells the user a money action landed when it did not.
  final bool ok;

  /// Server-supplied message, when it sent one.
  final String? error;

  /// Decoded body, or an empty map when the response was not JSON.
  final Map<String, dynamic> body;

  const ApiEnvelope.ok(this.body)
    : ok = true,
      error = null;

  const ApiEnvelope.failed(this.body, this.error) : ok = false;

  /// Reads [resp] as an envelope. A non-JSON body yields an error rather than
  /// throwing, so a proxy HTML error page cannot crash the caller.
  factory ApiEnvelope.from(http.Response resp) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(resp.body);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      body = <String, dynamic>{};
    }
    final message = (body['error'] ?? body['message'])?.toString();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return ApiEnvelope.failed(body, message);
    }
    // Legacy handlers predate the envelope and reply 200 with no `success`
    // key; treat its absence as success and only reject an explicit false.
    final success = body['success'];
    if (success == false) return ApiEnvelope.failed(body, message);
    return ApiEnvelope.ok(body);
  }
}