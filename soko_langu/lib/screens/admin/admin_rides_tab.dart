import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class AdminRidesTab extends StatefulWidget {
  const AdminRidesTab({super.key});

  @override
  State<AdminRidesTab> createState() => _AdminRidesTabState();
}

class _AdminRidesTabState extends State<AdminRidesTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/ride/admin-stats'),
        headers: headers,
        body: jsonEncode({}),
      );
      if (response.statusCode >= 400) throw Exception('Failed to load ride stats');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() {
        _stats = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          child: TabBar(
            controller: _subTabController,
            isScrollable: true,
            tabs: [
              Tab(text: '${context.tr('dashboard')} (Ride)'),
              Tab(text: context.tr('drivers')),
              Tab(text: '${context.tr('analytics')} (Ride)'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _buildOverviewTab(cs),
              _buildDriversTab(cs),
              _buildAnalyticsTab(cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(ColorScheme cs) {
    if (_loading) return const Center(child: GoogleLoadingPage());
    if (_error != null) return _buildError(cs);
    final s = _stats!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatRow(cs, [
            _statCard(cs, 'Active Trips', '${s['activeTripsCount'] ?? 0}', Icons.directions_car, Colors.blue),
            _statCard(cs, 'Online Drivers', '${s['onlineDriversCount'] ?? 0}', Icons.person_pin, Colors.green),
          ]),
          const SizedBox(height: 12),
          _buildStatRow(cs, [
            _statCard(cs, 'Today Revenue', 'TSh ${_fmt(s['todayRevenue'] ?? 0)}', Icons.monetization_on, Colors.amber, compact: true),
            _statCard(cs, 'Today Trips', '${s['todayCompletedTrips'] ?? 0}', Icons.check_circle, Colors.teal),
            _statCard(cs, 'Pending', '${s['pendingRequests'] ?? 0}', Icons.hourglass_empty, Colors.orange),
          ]),
          const SizedBox(height: 12),
          _buildStatRow(cs, [
            _statCard(cs, 'Cancellations (Today)', '${s['todayCancellations'] ?? 0}', Icons.cancel, Colors.red),
            _statCard(cs, 'Cancel Rate', '${s['cancellationRate'] ?? 0}', Icons.trending_down, Colors.redAccent),
            _statCard(cs, 'Total Drivers', '${s['totalDriversCount'] ?? 0}', Icons.people, Colors.indigo),
          ]),
          const SizedBox(height: 20),
          _buildSectionTitle(cs, 'Active Trips (${s['activeTripsCount'] ?? 0})'),
          const SizedBox(height: 8),
          ..._buildActiveTripsList(cs, s['activeTrips'] as List? ?? []),
          const SizedBox(height: 20),
          _buildSectionTitle(cs, 'Recent Trips (Last 50)'),
          const SizedBox(height: 8),
          ..._buildRecentTripsList(cs, s['recentTrips'] as List? ?? []),
        ],
      ),
    );
  }

  Widget _buildDriversTab(ColorScheme cs) {
    if (_loading) return const Center(child: GoogleLoadingPage());
    if (_error != null) return _buildError(cs);
    final drivers = _stats?['onlineDrivers'] as List? ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: drivers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(context.tr('no_online_drivers'), style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: drivers.length,
              itemBuilder: (context, i) {
                final d = drivers[i] as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                      child: const Icon(Icons.person_pin, color: Colors.green),
                    ),
                    title: Text(d['displayName'] ?? 'Unknown'),
                    subtitle: Text(
                      '${d['vehicleModel'] ?? ''} | ${d['vehicleReg'] ?? ''}'
                      ' | ⭐ ${d['rating'] ?? 0} | ${d['totalRides'] ?? 0} rides',
                    ),
                    trailing: Text(
                      d['phone'] ?? '',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAnalyticsTab(ColorScheme cs) {
    if (_loading) return const Center(child: GoogleLoadingPage());
    if (_error != null) return _buildError(cs);
    final s = _stats!;
    final cancelByReason = s['cancelByReason'] as Map? ?? {};
    final topDrivers = s['topDrivers'] as List? ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle(cs, context.tr('cancellation_reasons')),
          const SizedBox(height: 8),
          ...cancelByReason.entries.map((e) => Card(
                child: ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text(e.key),
                  trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              )),
          const SizedBox(height: 20),
          _buildSectionTitle(cs, context.tr('top_drivers')),
          const SizedBox(height: 8),
          if (topDrivers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('no_top_drivers'), style: TextStyle(color: cs.onSurfaceVariant)),
            )
          else
            ...topDrivers.map((d) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.star, color: Colors.amber)),
                    title: Text(context.trParams('driver_id_label', {'id': '${d['driverId']}'})),
                    trailing: Text('⭐ ${d['rating']}', style: const TextStyle(fontSize: 18)),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: cs.error),
          const SizedBox(height: 16),
          Text(context.tr('failed_load_ride_stats'), style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(context.tr('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(ColorScheme cs, List<Widget> cards) {
    return Row(
      children: cards
          .map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c)))
          .toList(),
    );
  }

  Widget _statCard(ColorScheme cs, String label, String value, IconData icon, Color color, {bool compact = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: compact ? 16 : 20, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: compact ? 10 : 12, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: compact ? 16 : 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ColorScheme cs, String title) {
    return Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary));
  }

  List<Widget> _buildActiveTripsList(ColorScheme cs, List trips) {
    if (trips.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr('no_active_trips'), style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      ];
    }
    return trips.map<Widget>((t) {
      final d = t as Map<String, dynamic>;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.withValues(alpha: 0.2),
            child: const Icon(Icons.directions_car, color: Colors.blue, size: 20),
          ),
          title: Text(context.trParams('trip_id_label', {'id': d['id'].toString().substring(0, 8)})),
          subtitle: Text('${d['pickupName'] ?? '?'} → ${d['dropoffName'] ?? '?'}\nStatus: ${d['status']}'),
          isThreeLine: true,
        ),
      );
    }).toList();
  }

  List<Widget> _buildRecentTripsList(ColorScheme cs, List trips) {
    if (trips.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr('no_recent_trips'), style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      ];
    }
    return trips.map<Widget>((t) {
      final d = t as Map<String, dynamic>;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: ListTile(
          dense: true,
          leading: Icon(d['status'] == 'trip_completed' ? Icons.check_circle : Icons.schedule, color: d['status'] == 'trip_completed' ? Colors.green : Colors.orange, size: 20),
          title: Text('${d['pickupName'] ?? '?'} → ${d['dropoffName'] ?? '?'}', style: const TextStyle(fontSize: 13)),
          subtitle: Text(context.trParams('status_fare_label', {'status': '${d['status']}', 'fare': _fmt(d['fare'] ?? 0)}), style: const TextStyle(fontSize: 11)),
        ),
      );
    }).toList();
  }

  String _fmt(dynamic val) {
    if (val == null) return '0';
    final n = (val is num) ? val : double.tryParse(val.toString()) ?? 0;
    return NumberFormat('#,##0', 'en_US').format(n);
  }
}
