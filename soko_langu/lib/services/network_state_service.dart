import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Coarse connectivity truth for the whole app.
///
/// Transport state alone lies (captive portals, dead Wi-Fi), so this
/// combines [connectivity_plus] with a lightweight `/health` probe and
/// exposes one [ChangeNotifier] instead of scattered checks.
enum NetworkStatus {
  /// Transport up and the API answered the health probe.
  online,

  /// Transport up but the API is unreachable or too slow to be useful.
  /// Repositories still attempt the network and fall back to cache.
  degraded,

  /// No usable transport at all.
  offline,
}

/// Single source of truth for connectivity (offline-first §4).
///
/// Owns the [connectivity_plus] subscription and the `/health` reachability
/// probe so features never check the network ad hoc. Repositories read
/// [canAttemptNetwork]; UI listens to [status] for banners/gates.
class NetworkStateService extends ChangeNotifier {
  NetworkStateService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _probeTimer;
  Timer? _debounceTimer;

  NetworkStatus _status = NetworkStatus.online;
  bool _started = false;
  int _consecutiveFailures = 0;

  NetworkStatus get status => _status;

  /// True unless the device has no transport. Degraded still tries the
  /// network because individual endpoints may recover before `/health`.
  bool get canAttemptNetwork => _status != NetworkStatus.offline;

  bool get isOnline => _status == NetworkStatus.online;
  bool get isOffline => _status == NetworkStatus.offline;

  /// Completes the next time we reach [NetworkStatus.online]. Used by the
  /// sync engine to wake the outbox without polling.
  Future<void> waitForOnline() async {
    if (isOnline) return;
    final completer = Completer<void>();
    void listener() {
      if (isOnline && !completer.isCompleted) completer.complete();
    }

    addListener(listener);
    try {
      await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      // Caller decides whether to keep waiting; never hang forever.
    } finally {
      removeListener(listener);
    }
  }

  /// Starts transport monitoring + the first reachability probe. Safe to
  /// call once from app startup; subsequent calls are ignored.
  void start() {
    if (_started) return;
    _started = true;
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen(_onTransportChanged);
    _evaluate();
  }

  void _onTransportChanged(List<ConnectivityResult> results) {
    final hasTransport = results.any((r) => r != ConnectivityResult.none);
    if (!hasTransport) {
      _debounceTimer?.cancel();
      _setStatus(NetworkStatus.offline);
      _scheduleProbe();
      return;
    }
    // Debounced so tunnel flaps don't thrash every repository listener.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), _evaluate);
  }

  Future<void> _evaluate() async {
    final results = await Connectivity().checkConnectivity();
    if (!results.any((r) => r != ConnectivityResult.none)) {
      _setStatus(NetworkStatus.offline);
      _scheduleProbe();
      return;
    }
    final reachable = await _probeServer();
    if (!reachable) {
      _consecutiveFailures++;
      _setStatus(NetworkStatus.degraded);
      _scheduleProbe();
      return;
    }
    _consecutiveFailures = 0;
    _probeTimer?.cancel();
    _setStatus(NetworkStatus.online);
  }

  // Single cheap HEAD/GET so offline detection never costs mobile data.
  Future<bool> _probeServer() async {
    try {
      final stopwatch = Stopwatch()..start();
      final resp = await _http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      stopwatch.stop();
      if (resp.statusCode >= 600) return false;
      // Answers, but slower than interactive use tolerates.
      if (stopwatch.elapsed > const Duration(seconds: 4)) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  // Backed-off re-probe while not online; cancelled on recovery.
  void _scheduleProbe() {
    _probeTimer?.cancel();
    final delaySeconds = (_consecutiveFailures * 5).clamp(5, 60);
    _probeTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!isOnline) _evaluate();
    });
  }

  void _setStatus(NetworkStatus next) {
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _probeTimer?.cancel();
    _debounceTimer?.cancel();
    _http.close();
    super.dispose();
  }
}
