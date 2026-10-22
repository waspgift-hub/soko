import 'package:flutter/material.dart';
import '../services/music_api.dart';

/// Operational diagnostics for the SokoVibe Music Worker.
/// Enable the entry point with --dart-define=ENABLE_ADMIN_DASHBOARD=true.
/// This is a diagnostics screen, not an authorization boundary.
class MusicAdminDashboardPage extends StatefulWidget {
  const MusicAdminDashboardPage({super.key, required this.api});

  final MusicApi api;

  @override
  State<MusicAdminDashboardPage> createState() => _MusicAdminDashboardPageState();
}

class _MusicAdminDashboardPageState extends State<MusicAdminDashboardPage> {
  final Map<String, _CheckResult> _checks = <String, _CheckResult>{};
  bool _runningAll = false;

  Future<void> _run(String key, String label, Future<String> Function() action) async {
    if (mounted) setState(() => _checks[key] = _CheckResult.running(label));
    final started = DateTime.now();
    try {
      final detail = await action();
      if (!mounted) return;
      setState(() => _checks[key] = _CheckResult.success(
        detail, DateTime.now().difference(started),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _checks[key] = _CheckResult.failure(
        error.toString(), DateTime.now().difference(started),
      ));
    }
  }

  Future<String> _health() async {
    final result = await widget.api.checkHealth();
    final jamendo = result['jamendo'];
    final ai = result['ai'];
    final serviceStatus = (result['status'] ?? 'unknown').toString();
    final jamendoConnected = jamendo is Map && jamendo['connected'] == true;
    final aiConfigured = ai is Map && ai['configured'] == true;
    final detail = 'Service: $serviceStatus · '
        'Jamendo: ${jamendoConnected ? 'connected' : 'not connected'} · '
        'AI: ${aiConfigured ? 'configured' : 'not configured'}';
    if (serviceStatus != 'healthy' || !jamendoConnected) {
      throw Exception('$detail. Check the Worker JAMENDO_CLIENT_ID secret and live Jamendo connectivity.');
    }
    // Backend health and Jamendo availability are independent of the optional
    // Workers AI binding. Report missing AI in the detail, but do not mark the
    // entire music service unhealthy; the dedicated lyrics check tests AI.
    return detail;
  }

  Future<String> _search() async {
    final tracks = await widget.api.search('afrobeat', limit: 5);
    return '${tracks.length} tracks returned for “afrobeat”.';
  }

  Future<String> _play() async {
    final tracks = await widget.api.search('afrobeat', limit: 1);
    if (tracks.isEmpty) throw Exception('Search returned no tracks to test play resolution.');
    final url = await widget.api.playUrl(tracks.first.id);
    if (!url.startsWith('https://')) throw Exception('Resolved stream URL was not HTTPS.');
    return 'Resolved track ${tracks.first.id} to a secure HTTPS stream URL.';
  }

  Future<String> _recommend() async {
    final tracks = await widget.api.recommend(genre: 'afrobeat', limit: 5);
    return '${tracks.length} recommendations returned.';
  }

  Future<String> _lyrics() async {
    final text = await widget.api.generateLyrics(
      theme: 'hope and a new beginning',
      genre: 'afrobeat',
      language: 'Swahili',
    );
    return 'Original lyrics generated (${text.length} characters).';
  }

  Future<void> _runAll() async {
    setState(() => _runningAll = true);
    await _run('health', 'Backend health', _health);
    await _run('search', 'Jamendo search', _search);
    await _run('play', 'Track play resolution', _play);
    await _run('recommend', 'Recommendations', _recommend);
    // Lyrics generation may consume Workers AI resources, so it is only run
    // when the operator explicitly taps its individual test button.
    if (mounted) setState(() => _runningAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final checks = <({String key, String title, IconData icon, Future<String> Function() run})>[
      (key: 'health', title: 'Backend health', icon: Icons.monitor_heart_outlined, run: _health),
      (key: 'search', title: 'Jamendo search', icon: Icons.search, run: _search),
      (key: 'play', title: 'Track play resolution', icon: Icons.play_circle_outline, run: _play),
      (key: 'recommend', title: 'Recommendations', icon: Icons.auto_awesome_outlined, run: _recommend),
      (key: 'lyrics', title: 'AI lyrics generation', icon: Icons.lyrics_outlined, run: _lyrics),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music admin dashboard'),
        actions: [
          IconButton(
            tooltip: 'Run safe checks',
            onPressed: _runningAll ? null : _runAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Service operations', style: Theme.of(context).textTheme.titleLarge)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Run live checks against the configured Cloudflare Worker. '
                    'Results show only what each endpoint confirms; this screen does not report user or revenue analytics.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(widget.api.baseUrl, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _runningAll ? null : _runAll,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run backend checks'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final check in checks)
            Card(
              child: ListTile(
                leading: Icon(check.icon),
                title: Text(check.title),
                subtitle: _resultWidget(_checks[check.key]),
                trailing: IconButton(
                  tooltip: 'Run ${check.title}',
                  onPressed: _checks[check.key]?.running == true
                      ? null
                      : () => _run(check.key, check.title, check.run),
                  icon: const Icon(Icons.play_arrow),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Important: this is an operational diagnostics view, not a secured admin console. '
            'Do not use a client-side visibility flag as authorization. User management, moderation, '
            'and analytics need authenticated admin endpoints and persistent data.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _resultWidget(_CheckResult? result) {
    if (result == null) return const Text('Not tested yet');
    if (result.running) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: LinearProgressIndicator(),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.detail),
          const SizedBox(height: 3),
          Text(
            '${result.success ? 'PASS' : 'FAIL'} · ${result.duration?.inMilliseconds ?? 0} ms',
            style: TextStyle(
              color: result.success ? Colors.green : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckResult {
  const _CheckResult({
    required this.detail,
    required this.success,
    required this.running,
    this.duration,
  });

  factory _CheckResult.running(String label) => _CheckResult(
    detail: '$label is running…', success: false, running: true,
  );

  factory _CheckResult.success(String detail, Duration duration) => _CheckResult(
    detail: detail, success: true, running: false, duration: duration,
  );

  factory _CheckResult.failure(String detail, Duration duration) => _CheckResult(
    detail: detail, success: false, running: false, duration: duration,
  );

  final String detail;
  final bool success;
  final bool running;
  final Duration? duration;
}
