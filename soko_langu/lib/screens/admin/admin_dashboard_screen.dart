import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../services/analytics_service.dart';
import '../../shared/loading_widget.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  AnalyticsData? _analytics;
  bool _loading = true;
  bool _isAdmin = false;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loadingUsers = false, _loadingProducts = false, _loadingOrders = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
    await Future.wait([_loadAnalytics(), _loadUsers(), _loadProducts(), _loadOrders()]);
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

  Future<void> _loadOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('orders').get();
      if (mounted) {
        setState(() => _orders = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
      }
    } catch (e) {
      debugPrint('Admin loadOrders: $e');
    }
    if (mounted) setState(() => _loadingOrders = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(body: GoogleLoadingPage());
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('admin_dashboard'))),
        body: LoadingWidget(message: context.tr('loading')),
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
              Future.wait([_loadAnalytics(), _loadUsers(), _loadProducts(), _loadOrders()])
                  .then((_) => setState(() => _loading = false));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.dashboard), text: context.tr('stats')),
            Tab(icon: const Icon(Icons.analytics), text: context.tr('stats')),
            Tab(icon: const Icon(Icons.people), text: context.tr('users')),
            Tab(icon: const Icon(Icons.inventory_2), text: context.tr('products')),
            Tab(icon: const Icon(Icons.receipt_long), text: context.tr('orders')),
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
            _buildOrdersTab(),
          ],
        ),
      ),
    );
  }

  // ─── DASHBOARD TAB ─────────────────────────────────────────────
  Widget _buildDashboardTab() {
    final a = _analytics!;
    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kpiRow([
            _kpiCard('Total Users', '${a.totalUsers}', Icons.people, Colors.blue, a.newUsersToday),
            _kpiCard('Products', '${a.totalProducts}', Icons.inventory_2, Colors.green, a.activeProducts),
          ]),
          const SizedBox(height: 12),
          _kpiRow([
            _kpiCard('Orders', '${a.totalOrders}', Icons.receipt_long, Colors.orange, a.totalRevenue),
            _kpiCard('Revenue', 'TZS ${a.totalRevenue.toStringAsFixed(0)}', Icons.account_balance, Colors.purple, a.revenueToday),
          ]),
          const SizedBox(height: 12),
          _kpiRow([
            _kpiCard('New Today', '${a.newUsersToday}', Icons.person_add, Colors.teal, null),
            _kpiCard('Reports', '${a.totalReports}', Icons.flag, Colors.red, null),
          ]),
          const SizedBox(height: 20),
          Text('Revenue (7 days)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildBarChart(
            a.revenueOverTime.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            Colors.green,
            (v) => 'TZS $v',
          ),
          const SizedBox(height: 20),
          Text('User Growth (7 days)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildBarChart(
            a.userGrowth.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            Colors.blue,
            (v) => '$v users',
          ),
          const SizedBox(height: 20),
          Text('Order Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildOrderStatusPie(a.ordersByStatus),
          const SizedBox(height: 20),
          _buildQuickActions(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _kpiRow(List<Widget> cards) {
    return Row(children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList());
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color, dynamic sub) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: TextStyle(color: color.withAlpha(180), fontSize: 12)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub is double ? 'TZS ${sub.toStringAsFixed(0)} today' : '$sub today',
                style: TextStyle(color: color.withAlpha(150), fontSize: 10)),
          ],
        ],
      ),
    );
  }

  // ─── BAR CHART ───────────────────────────────────────────
  Widget _buildBarChart(List<BarEntry> entries, Color color, String Function(double) format) {
    if (entries.isEmpty) return const SizedBox();
    final maxVal = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxBar = maxVal > 0 ? maxVal : 1.0;
    return Container(
      height: 160,
      padding: const EdgeInsets.only(top: 16, bottom: 4, left: 4, right: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((e) {
          final fraction = e.value / maxBar;
          final dayLabel = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][e.date.weekday - 1];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(format(e.value), style: TextStyle(fontSize: 8, color: color.withAlpha(180))),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    child: Container(
                      height: 140 * fraction.clamp(0.02, 1.0),
                      width: double.infinity,
                      color: color.withAlpha(160),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(dayLabel, style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── ORDER STATUS PIE ────────────────────────────────────
  Widget _buildOrderStatusPie(Map<String, int> statusMap) {
    final colors = {
      'pending': Colors.orange,
      'confirmed': Colors.blue,
      'processing': Colors.purple,
      'shipped': Colors.teal,
      'delivered': Colors.green,
      'cancelled': Colors.red,
    };
    final total = statusMap.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No orders yet')));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: statusMap.entries.map((e) {
            final pct = (e.value / total * 100).toStringAsFixed(1);
            final c = colors[e.key] ?? Colors.grey;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / total,
                        backgroundColor: c.withAlpha(30),
                        valueColor: AlwaysStoppedAnimation(c),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 50, child: Text('$pct%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── QUICK ACTIONS ─────────────────────────────────────
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _actionChip(Icons.monetization_on, 'Ad Revenue', () {
            context.push(AppRoutes.adminAdRevenue);
          }),
          _actionChip(Icons.notifications, 'Send Notification', _showSendNotificationDialog),
            _actionChip(Icons.download, 'Export Users CSV', _exportUsersCsv),
            _actionChip(Icons.settings, 'Maintenance Mode', _toggleMaintenance),
          ],
        ),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }

  // ─── SEND NOTIFICATION DIALOG ──────────────────────────
  void _showSendNotificationDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Push Notification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Body', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              await _analyticsService.sendPushToAll(titleCtrl.text, bodyCtrl.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notification sent to all users')),
                );
              }
            },
            child: const Text('Send to All'),
          ),
        ],
      ),
    );
  }

  // ─── EXPORT USERS CSV ─────────────────────────────────
  Future<void> _exportUsersCsv() async {
    final buffer = StringBuffer();
    buffer.writeln('UID,Name,Email,Phone,Tier,Admin,Suspended,Created');
    for (final u in _users) {
      buffer.writeln(
        '"${u['uid']}","${u['displayName'] ?? ''}","${u['email'] ?? ''}","${u['phone'] ?? ''}",'
        '"${u['accountTier'] ?? 'free'}","${u['isAdmin'] == true}","${u['isSuspended'] == true}","${u['createdAt'] ?? ''}"',
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
    final a = _analytics!;
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
            Colors.green,
            (v) => 'TZS $v',
          ),
          const SizedBox(height: 20),
          Text('New Users (7 days)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildBarChart(
            a.userGrowth.map((m) => BarEntry(m.date, m.count.toDouble())).toList(),
            Colors.blue,
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
                        backgroundColor: Colors.grey.withAlpha(30),
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
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadUsers,
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                final name = u['displayName'] ?? u['email'] ?? 'Unknown';
                final tier = u['accountTier'] ?? 'free';
                final suspended = u['isSuspended'] == true;
                final phone = u['phone'] ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: suspended ? Colors.red : Colors.green,
                      child: Text(name.toString()[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text('$name${suspended ? ' (Suspended)' : ''}'),
                    subtitle: Text('Tier: $tier | $phone'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _updateUser(u['uid'] as String, v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'silver', child: Text('Set Silver')),
                        const PopupMenuItem(value: 'premium', child: Text('Set Premium')),
                        const PopupMenuItem(value: 'free', child: Text('Set Free')),
                        const PopupMenuItem(value: 'toggle_admin', child: Text('Toggle Admin')),
                        PopupMenuItem(value: suspended ? 'unsuspend' : 'suspend', child: Text(suspended ? 'Unsuspend' : 'Suspend')),
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
      Map<String, dynamic> body = {};
      if (action == 'silver' || action == 'premium' || action == 'free') {
        body = {'accountTier': action};
      } else if (action == 'toggle_admin') {
        final user = _users.firstWhere((u) => u['uid'] == uid);
        body = {'isAdmin': user['isAdmin'] != true};
      } else if (action == 'suspend') {
        body = {'isSuspended': true};
      } else if (action == 'unsuspend') {
        body = {'isSuspended': false};
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update(body);
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
          final name = p['name'] ?? 'Unknown';
          final price = p['price'] ?? 0;
          final active = p['isActive'] != false;
          final featured = p['isFeatured'] == true;
          final seller = p['sellerName'] ?? 'Unknown';
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 48, height: 48, color: Colors.grey[200],
                  child: p['images'] != null && (p['images'] as List).isNotEmpty
                      ? CachedNetworkImage(imageUrl: (p['images'] as List).first, fit: BoxFit.cover)
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('$seller — TZS $price${!active ? ' [HIDDEN]' : ''}${featured ? ' ⭐' : ''}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _updateProduct(p['id'] as String, v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: active ? 'deactivate' : 'activate', child: Text(active ? context.tr('deactivate') : context.tr('activate'))),
                  PopupMenuItem(value: featured ? 'unfeature' : 'feature', child: Text(featured ? context.tr('remove_featured') : context.tr('mark_featured'))),
                  PopupMenuItem(value: 'delete', child: Text(context.tr('delete'), style: TextStyle(color: Colors.red))),
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
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('delete'), style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (confirm != true) return;
        await FirebaseFirestore.instance.collection('products').doc(id).delete();
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

  // ─── ORDERS TAB ───────────────────────────────────────────────
  Widget _buildOrdersTab() {
    if (_loadingOrders) return const GoogleLoadingPage();
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final o = _orders[i];
          final id = o['id'] as String? ?? '';
          final status = o['status'] as String? ?? 'pending';
          final total = o['totalAmount'] ?? o['productPrice'] ?? 0;
          final buyer = o['buyerName'] ?? 'Unknown';
          final items = o['items'] as List?;
          final itemNames = items != null ? items.map((it) => it['name'] ?? '').join(', ') : o['productName'] ?? '';
          final statusColors = {
            'pending': Colors.orange, 'confirmed': Colors.blue, 'processing': Colors.purple,
            'shipped': Colors.teal, 'delivered': Colors.green, 'cancelled': Colors.red,
          };
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: ListTile(
              title: Text('#${id.length > 8 ? id.substring(0, 8) : id} — $buyer',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('$itemNames — TZS $total'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (statusColors[status] ?? Colors.grey).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: status,
                  underline: const SizedBox(),
                  items: ['pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: statusColors[s] ?? Colors.grey, fontSize: 12))))
                      .toList(),
                  onChanged: (v) { if (v != null) _updateOrder(id, v); },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateOrder(String id, String status) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(id).update({'status': status});
      _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order updated to $status')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
