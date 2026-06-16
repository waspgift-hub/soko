import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../services/analytics_service.dart';
import '../../services/api_config.dart';
import '../../services/fraud_prevention_service.dart';
import '../../widgets/google_loading.dart';
import '../report/admin_reports_screen.dart';
import 'admin_wallet_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class BarEntry {
  final DateTime date;
  final double value;
  BarEntry(this.date, this.value);
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _analyticsService = AnalyticsService();
  final _fraudService = FraudPreventionService();
  AnalyticsData? _analytics;
  bool _loading = true;
  bool _isAdmin = false;
  Map<String, int> _fraudStats = {};

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _products = [];
  bool _loadingUsers = false, _loadingProducts = false;
  String _userSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _checkAdmin();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('not_logged_in'))),
        );
      }
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    if (data?['isAdmin'] != true && user.email != 'admin@soko-langu.com') {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('access_denied'))),
        );
      }
      return;
    }
    setState(() => _isAdmin = true);
    try {
      await Future.wait([_loadAnalytics(), _loadUsers(), _loadProducts(), _loadFraudStats()]);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAnalytics() async {
    final data = await _analyticsService.loadAnalytics();
    if (mounted) setState(() => _analytics = data);
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      if (mounted) {
        setState(() => _users = snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList());
      }
    } catch (e) {
      debugPrint('Admin loadUsers: $e');
    }
    if (mounted) setState(() => _loadingUsers = false);
  }

  Future<void> _loadFraudStats() async {
    try {
      final stats = await _fraudService.getFraudStats();
      if (mounted) setState(() => _fraudStats = stats);
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('products').get();
      if (mounted) {
        setState(() => _products = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
      }
    } catch (e) {
      debugPrint('Admin loadProducts: $e');
    }
    if (mounted) setState(() => _loadingProducts = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(body: GoogleLoadingPage());
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('admin_dashboard'))),
        body: const GoogleLoadingPage(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('admin_dashboard')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              Future.wait([_loadAnalytics(), _loadUsers(), _loadProducts(), _loadFraudStats()])
                  .then((_) => setState(() => _loading = false));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.dashboard), text: context.tr('dashboard')),
            Tab(icon: const Icon(Icons.analytics), text: context.tr('analytics')),
            Tab(icon: const Icon(Icons.people), text: context.tr('users')),
            Tab(icon: const Icon(Icons.inventory_2), text: context.tr('products')),
            Tab(icon: const Icon(Icons.flag), text: context.tr('reports')),
            Tab(icon: const Icon(Icons.security), text: context.tr('fraud')),
            Tab(icon: const Icon(Icons.payments), text: context.tr('payout')),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildDashboardTab(),
            _buildAnalyticsTab(),
            _buildUsersTab(),
            _buildProductsTab(),
            _buildReportsTab(),
            _buildFraudTab(),
            _buildPayoutTab(),
          ],
        ),
      ),
    );
  }

  // ─── DASHBOARD TAB ─────────────────────────────────────────────
  Widget _buildDashboardTab() {
    final a = _analytics ?? AnalyticsData();
    final cs = Theme.of(context).colorScheme;
    final nf = NumberFormat('#,###', 'en');
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadAnalytics(), _loadFraudStats()]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _kpiCard(
            icon: Icons.people,
            label: context.tr('total_users'),
            value: '${a.totalUsers}',
            color: cs.primary,
            sub: '${a.newUsersToday} ${context.tr('new_today')}',
            nf: nf,
          ),
          const SizedBox(height: 10),
          _kpiCard(
            icon: Icons.inventory_2,
            label: context.tr('products'),
            value: '${a.totalProducts}',
            color: cs.secondary,
            sub: '${a.activeProducts} ${context.tr('active')}',
            nf: nf,
          ),
          const SizedBox(height: 10),
          _kpiCard(
            icon: Icons.receipt_long,
            label: context.tr('orders'),
            value: '${a.totalOrders}',
            color: cs.tertiary,
            sub: 'TZS ${nf.format(a.totalRevenue)} ${context.tr('total_revenue')}',
            nf: nf,
          ),
          const SizedBox(height: 10),
          _kpiCard(
            icon: Icons.account_balance,
            label: context.tr('revenue_today'),
            value: 'TZS ${nf.format(a.revenueToday)}',
            color: cs.secondary,
            sub: '${a.newUsersToday} ${context.tr('new_users')}',
            nf: nf,
          ),
          const SizedBox(height: 20),
          _buildSectionHeader(context.tr('revenue_7_days'), cs),
          const SizedBox(height: 8),
          _buildBarChart(
            a.revenueOverTime.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            cs.primary,
            (v) => 'TZS ${nf.format(v.toInt())}',
            nf,
          ),
          const SizedBox(height: 20),
          _buildSectionHeader(context.tr('user_growth_7_days'), cs),
          const SizedBox(height: 8),
          _buildBarChart(
            a.userGrowth.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            cs.secondary,
            (v) => nf.format(v.toInt()),
            nf,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(context.tr('quick_actions'), cs),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme cs) {
    return Row(
      children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? sub,
    NumberFormat? nf,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.71))),
              ],
            ),
          ),
          if (sub != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(sub, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }

  // ─── BAR CHART ───────────────────────────────────────────
  Widget _buildBarChart(List<BarEntry> entries, Color color, String Function(double) format, [NumberFormat? nf]) {
    if (entries.isEmpty) return const SizedBox();
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxBar = maxVal > 0 ? maxVal : 1.0;
    return Container(
      height: 180,
      padding: const EdgeInsets.only(top: 20, bottom: 4, left: 8, right: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((e) {
          final fraction = e.value / maxBar;
          final dayLabel = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][e.date.weekday - 1];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(format(e.value), style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.71), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    child: Container(
                      height: 140 * fraction.clamp(0.03, 1.0),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.5), color],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(dayLabel, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── QUICK ACTIONS ─────────────────────────────────────
  Widget _buildQuickActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _actionTile(Icons.account_balance_wallet, context.tr('wallet'), Theme.of(context).colorScheme.secondary, () => context.push(AppRoutes.adminWallet)),
        _actionTile(Icons.monetization_on, context.tr('ad_revenue'), Theme.of(context).colorScheme.primary, () => context.push(AppRoutes.adminAdRevenue)),
        _actionTile(Icons.notifications, context.tr('send_notification'), Theme.of(context).colorScheme.tertiary, _showSendNotificationDialog),
        _actionTile(Icons.download, context.tr('export_users'), Theme.of(context).colorScheme.primary, _exportUsersCsv),
        _actionTile(Icons.settings, context.tr('maintenance'), Theme.of(context).colorScheme.error, _toggleMaintenance),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: (MediaQuery.of(context).size.width - 52) / 3,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SEND NOTIFICATION DIALOG ──────────────────────────
  void _showSendNotificationDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('send_push_notification')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(labelText: context.tr('title'), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: InputDecoration(labelText: context.tr('body'), border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              await _analyticsService.sendPushToAll(titleCtrl.text, bodyCtrl.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('notification_sent_all'))),
                );
              }
            },
            child: Text(context.tr('send_to_all')),
          ),
        ],
      ),
    );
  }

  // ─── EXPORT USERS CSV ─────────────────────────────────
  Future<void> _exportUsersCsv() async {
    final buffer = StringBuffer();
      buffer.writeln('UID,Name,Email,Phone,Admin,Suspended,Created');
    for (final u in _users) {
      buffer.writeln(
        '"${u['uid']}","${u['displayName'] ?? ''}","${u['email'] ?? ''}","${u['phone'] ?? ''}",'
        '"${u['isAdmin'] == true}","${u['isSuspended'] == true}","${u['createdAt'] ?? ''}"',
      );
    }
    await FirebaseFirestore.instance.collection('admin_exports').add({
      'type': 'users_csv',
      'data': buffer.toString(),
      'createdAt': FieldValue.serverTimestamp(),
      'exportedBy': FirebaseAuth.instance.currentUser?.uid,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Users CSV saved to admin_exports collection')),
      );
    }
  }

  // ─── TOGGLE MAINTENANCE ───────────────────────────────
  Future<void> _toggleMaintenance() async {
    final enabled = await _analyticsService.getMaintenanceMode();
    await _analyticsService.toggleMaintenanceMode(!enabled);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maintenance mode: ${!enabled ? 'ON' : 'OFF'}')),
      );
    }
  }

  // ─── ANALYTICS TAB ───────────────────────────────────────
  Widget _buildAnalyticsTab() {
    final a = _analytics ?? AnalyticsData();
    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('User Analytics', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _statRow('Total Users', '${a.totalUsers}', 'New Today: ${a.newUsersToday}', 'New Month: ${a.newUsersThisMonth}'),
          const SizedBox(height: 16),
          Text('Product Analytics', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _statRow('Total Products', '${a.totalProducts}', 'Active: ${a.activeProducts}', 'Inactive: ${a.inactiveProducts}'),
          const SizedBox(height: 16),
          Text('Revenue', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _statRow(
            'Total Revenue', 'TZS ${a.totalRevenue.toStringAsFixed(0)}',
            'Today: TZS ${a.revenueToday.toStringAsFixed(0)}',
            'Month: TZS ${a.revenueThisMonth.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 20),
          Text('Category Distribution', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildCategoryList(a.productsByCategory, a.totalProducts),
          const SizedBox(height: 20),
          Text('Revenue Trend (7 days)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildBarChart(
            a.revenueOverTime.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            Theme.of(context).colorScheme.primary,
            (v) => 'TZS $v',
          ),
          const SizedBox(height: 20),
          Text('New Users (7 days)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildBarChart(
            a.userGrowth.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            Theme.of(context).colorScheme.secondary,
            (v) => '$v',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _statRow(String title, String mainValue, String sub1, String sub2) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(mainValue, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(sub1, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 2),
                Text(sub2, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(Map<String, int> catMap, int total) {
    if (catMap.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No products')));
    final sorted = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sorted.map((e) {
            final pct = (e.value / total * 100).toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(e.key, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / total,
                        backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 40, child: Text('$pct%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── USERS TAB ───────────────────────────────────────────────
  Widget _buildUsersTab() {
    if (_loadingUsers) return const GoogleLoadingPage();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search users...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (q) => setState(() => _userSearchQuery = q.toLowerCase()),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadUsers,
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
              itemCount: _users.where((u) {
                final name = (u['displayName'] ?? u['email'] ?? '').toString().toLowerCase();
                final phone = (u['phone'] ?? '').toString().toLowerCase();
                return name.contains(_userSearchQuery) || phone.contains(_userSearchQuery);
              }).length,
              itemBuilder: (_, i) {
                final filtered = _users.where((u) {
                  final name = (u['displayName'] ?? u['email'] ?? '').toString().toLowerCase();
                  final phone = (u['phone'] ?? '').toString().toLowerCase();
                  return name.contains(_userSearchQuery) || phone.contains(_userSearchQuery);
                }).toList();
                final u = filtered[i];
                final name = u['displayName'] ?? u['email'] ?? context.tr('unknown');
                final suspended = u['isSuspended'] == true;
                final phone = u['phone'] ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: suspended ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                      child: Text(name.toString()[0].toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.surface)),
                    ),
                    title: Text('$name${suspended ? ' (Suspended)' : ''}'),
                    subtitle: Text(phone),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _updateUser(u['uid'] as String, v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'toggle_admin', child: Text('Toggle Admin')),
                        PopupMenuItem(value: suspended ? 'unsuspend' : 'suspend', child: Text(suspended ? 'Unsuspend' : 'Suspend')),
                        const PopupMenuItem(value: 'full_delete', child: Text('Full Delete', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateUser(String uid, String action) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final authHeaders = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      if (action == 'full_delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete User Forever'),
            content: const Text('This will permanently delete this user and all their data (orders, products, reviews, etc.). Are you sure?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete Forever', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (confirm != true) return;
        final resp = await http.delete(
          Uri.parse('${ApiConfig.baseUrl}/api/admin/users/$uid/full-delete'),
          headers: authHeaders,
        );
        if (resp.statusCode != 200) {
          throw Exception(jsonDecode(resp.body)['error'] ?? 'Delete failed');
        }
        _loadUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User permanently deleted')));
        }
        return;
      }
      Map<String, dynamic> body = {};
      if (action == 'toggle_admin') {
        final user = _users.firstWhere((u) => u['uid'] == uid);
        body = {'isAdmin': user['isAdmin'] != true};
      } else if (action == 'suspend') {
        body = {'isSuspended': true};
      } else if (action == 'unsuspend') {
        body = {'isSuspended': false};
      }
      final resp = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/users/$uid'),
        headers: authHeaders,
        body: jsonEncode({'updates': body}),
      );
      if (resp.statusCode != 200) {
        throw Exception(jsonDecode(resp.body)['error'] ?? 'Update failed');
      }
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User updated: $action')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ─── PRODUCTS TAB ─────────────────────────────────────────────
  Widget _buildProductsTab() {
    if (_loadingProducts) return const GoogleLoadingPage();
    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.builder(
        itemCount: _products.length,
        itemBuilder: (_, i) {
          final p = _products[i];
          final name = p['name'] ?? context.tr('unknown');
          final price = p['price'] ?? 0;
          final active = p['isActive'] != false;
          final featured = p['isFeatured'] == true;
          final seller = p['sellerName'] ?? context.tr('unknown');
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48, height: 48, color: Theme.of(context).colorScheme.outlineVariant,
                  child: p['images'] != null && (p['images'] as List).isNotEmpty
                      ? CachedNetworkImage(imageUrl: (p['images'] as List).first, fit: BoxFit.cover)
                      : Icon(Icons.image, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('$seller — TZS $price${!active ? ' [HIDDEN]' : ''}${featured ? ' ⭐' : ''}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _updateProduct(p['id'] as String, v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: active ? 'deactivate' : 'activate', child: Text(active ? context.tr('deactivate') : context.tr('activate'))),
                  PopupMenuItem(value: featured ? 'unfeature' : 'feature', child: Text(featured ? context.tr('remove_featured') : context.tr('mark_featured'))),
                  PopupMenuItem(value: 'delete', child: Text(context.tr('delete'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateProduct(String id, String action) async {
    try {
      if (action == 'delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('delete_product')),
            content: Text(context.tr('delete_confirm')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        );
        if (confirm != true) return;
        try {
          final token = await FirebaseAuth.instance.currentUser?.getIdToken();
          final resp = await http.delete(
            Uri.parse('${ApiConfig.baseUrl}/api/admin/products/$id'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );
          final result = jsonDecode(resp.body);
          if (result['success'] != true) {
            throw Exception(result['error'] ?? 'Delete failed');
          }
        } catch (e) {
          throw Exception(e.toString());
        }
        _loadProducts();
        return;
      }
      Map<String, dynamic> body = {};
      if (action == 'activate') { body = {'isActive': true}; }
      else if (action == 'deactivate') { body = {'isActive': false}; }
      else if (action == 'feature') { body = {'isFeatured': true, 'featuredUntil': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)))}; }
      else if (action == 'unfeature') { body = {'isFeatured': false, 'featuredUntil': null}; }
      await FirebaseFirestore.instance.collection('products').doc(id).update(body);
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Product updated: $action')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ─── REPORTS TAB ─────────────────────────────────────────────
  Widget _buildReportsTab() {
    return const AdminReportsScreen(embedded: true);
  }

  // ─── PAYOUT TAB ───────────────────────────────────────────────
  Widget _buildPayoutTab() {
    return const AdminWalletScreen();
  }

  // ─── FRAUD TAB ────────────────────────────────────────────────
  Widget _buildFraudTab() {
    return StreamBuilder<List<FraudAlert>>(
      stream: _fraudService.getFraudAlerts(resolved: false),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const GoogleLoadingPage();
        final alerts = snap.data ?? [];
        if (alerts.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                  const SizedBox(height: 16),
                  Text('No active fraud alerts', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text('Test mode: ${_fraudService.isTestMode ? "ON (alerts logged only)" : "OFF (production)"}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6))),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _loadFraudStats,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: alerts.length,
            itemBuilder: (_, i) => _buildFraudCard(alerts[i]),
          ),
        );
      },
    );
  }

  Widget _buildFraudCard(FraudAlert alert) {
    final severityColor = alert.severity == 'high'
        ? Theme.of(context).colorScheme.error
        : alert.severity == 'medium'
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.tertiary;
    final dateStr = DateFormat('MMM dd, HH:mm').format(alert.detectedAt);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: severityColor.withValues(alpha: 0.10),
          child: Icon(Icons.warning_amber, color: severityColor, size: 22),
        ),
        title: Text(alert.sellerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('${alert.description}\n$dateStr', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        trailing: TextButton(
          onPressed: () => _fraudService.markResolved(alert.id),
          child: Text(context.tr('dismiss'), style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

}
