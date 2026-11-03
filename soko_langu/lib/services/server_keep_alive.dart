import 'dart:async';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Pings the Render free-tier backend while the app is running so it never
/// falls asleep mid-session. Pure fire-and-forget — payment initiation has its
/// own retries, so keep-alive failures must never surface to the UI.
class ServerKeepAlive {
  ServerKeepAlive._();

  static final ServerKeepAlive instance = ServerKeepAlive._();

  static const _pingInterval = Duration(minutes: 10);
  Timer? _timer;

  static bool get isRunning => instance._timer?.isActive ?? false;

  void start() {
    _timer?.cancel();
    _ping();
    _timer = Timer.periodic(_pingInterval, (_) => _ping());
  }

  Future<void> _ping() async {
    try {
      await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Cold-start box or poor network — the warm-up retry handles real calls.
    }
  }
}