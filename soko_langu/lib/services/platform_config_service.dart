import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/transaction_model.dart';
import 'api_config.dart';

/// Fetches platform-wide, owner-controlled settings that money depends on.
///
/// Today this is the Soko Vibe commission rate. The owner sets it from the web
/// admin panel (Mipangilio → Fedha); the server charges whatever is stored
/// there. The app previously carried its own hardcoded 3.5%, so a change in the
/// panel left the checkout quoting a fee the server never took — the two
/// numbers only matched by coincidence.
class PlatformConfigService {
  PlatformConfigService._();
  static final PlatformConfigService instance = PlatformConfigService._();

  static const _timeout = Duration(seconds: 8);

  StreamController<void>? _changes;
  bool _loaded = false;

  /// Current rate as a fraction (0.035 = 3.5%).
  double get commissionRate => TransactionFeeBreakdown.platformCommissionPercent;

  /// Emits after a successful refresh so open checkout screens can re-total.
  Stream<void> get onChanged {
    _changes ??= StreamController<void>.broadcast();
    return _changes!.stream;
  }

  /// Loads the rate once per app launch.
  ///
  /// Never throws and never blocks startup: on any failure the previous value
  /// stands. That matters because the fallback is a *displayed* number — if the
  /// fetch failed we must not silently reset the rate to 0 and under-quote the
  /// buyer, nor invent a rate the server will not charge.
  Future<void> loadCommissionRate() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final res = await http
          .get(Uri.parse(ApiConfig.v1('/admin/config/commission')))
          .timeout(_timeout);
      if (res.statusCode != 200) return;
      final body = res.body;
      // Accepts both `{data:{...}}` and a bare `{...}` envelope.
      final pct = _extractPercent(body);
      if (pct == null) return;
      TransactionFeeBreakdown.platformCommissionPercent = pct;
      if (kDebugMode) debugPrint('[PlatformConfig] commission = ${pct * 100}%');
      _changes?.add(null);
    } catch (e) {
      // Offline or server down: keep whatever the app already assumed. The
      // server re-reads the same setting, so a stale client can only make the
      // displayed fee differ, never the amount actually charged.
      if (kDebugMode) debugPrint('[PlatformConfig] rate fetch skipped: $e');
    }
  }

  /// Parses `platformCommissionPct` and rejects anything outside 0–1.
  ///
  /// A percent (3.5) rather than a fraction (0.035) is coerced down, because an
  /// admin typing "3.5" into a field labelled "%" is the natural mistake and
  /// charging 350% must not be reachable.
  static double? _extractPercent(String body) {
    final m = RegExp(r'"platformCommissionPct"\s*:\s*(-?\d+(?:\.\d+)?)')
        .firstMatch(body);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
    if (v > 1) return v > 100 ? null : v / 100;
    return v;
  }
}