import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/payment_service.dart';
import '../../services/api_config.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _paymentService = PaymentService();
  Map<String, double> _stats = {};
  bool _loading = true;
  bool _isAdmin = false;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loadingUsers = false;
  bool _loadingProducts = false;
  bool _loadingOrders = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not logged in')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Access denied')));
      }
      return;
    }
    setState(() => _isAdmin = true);
    _loadStats();
    _loadUsers();
    _loadProducts();
    _loadOrders();
  }

  Future<void> _loadStats() async {
    final stats = await _paymentService.getRevenueStats();
    if (mounted)
      setState(() {
        _stats = stats;
        _loading = false;
      });
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/users'),
        headers: {'x-admin-secret': 'soko123'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _users = List<Map<String, dynamic>>.from(data['users'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingUsers = false);
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/products'),
        headers: {'x-admin-secret': 'soko123'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _products = List<Map<String, dynamic>>.from(data['products'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingProducts = false);
  }

  Future<void> _loadOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/orders'),
        headers: {'x-admin-secret': 'soko123'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _orders = List<Map<String, dynamic>>.from(data['orders'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingOrders = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Products'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Orders'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Stats'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(),
          _buildProductsTab(),
          _buildOrdersTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  // ============================================================
  // USERS TAB
  // ============================================================
  Widget _buildUsersTab() {
    if (_loadingUsers) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search users...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (q) => setState(() {}),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadUsers,
            child: ListView.builder(
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                final name = u['displayName'] ?? u['email'] ?? 'Unknown';
                final tier = u['accountTier'] ?? 'free';
                final suspended = u['isSuspended'] == true;
                final phone = u['phone'] ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: suspended ? Colors.red : Colors.green,
                      child: Text(
                        name.toString()[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text('$name${suspended ? ' (Suspended)' : ''}'),
                    subtitle: Text('Tier: $tier | $phone'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _updateUser(u['uid'], v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'silver',
                          child: Text('Set Silver'),
                        ),
                        const PopupMenuItem(
                          value: 'premium',
                          child: Text('Set Premium'),
                        ),
                        const PopupMenuItem(
                          value: 'free',
                          child: Text('Set Free'),
                        ),
                        const PopupMenuItem(
                          value: 'toggle_admin',
                          child: Text('Toggle Admin'),
                        ),
                        PopupMenuItem(
                          value: suspended ? 'unsuspend' : 'suspend',
                          child: Text(suspended ? 'Unsuspend' : 'Suspend'),
                        ),
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

      await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/users/$uid'),
        headers: {
          'Content-Type': 'application/json',
          'x-admin-secret': 'soko123',
        },
        body: jsonEncode(body),
      );
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('User updated: $action')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ============================================================
  // PRODUCTS TAB
  // ============================================================
  Widget _buildProductsTab() {
    if (_loadingProducts)
      return const Center(child: CircularProgressIndicator());
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
                  width: 48,
                  height: 48,
                  color: Colors.grey[200],
                  child: p['images'] != null && (p['images'] as List).isNotEmpty
                      ? Image.network(
                          (p['images'] as List).first,
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '$seller — TZS $price${!active ? ' [HIDDEN]' : ''}${featured ? ' ⭐' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _updateProduct(p['id'], v),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: active ? 'deactivate' : 'activate',
                    child: Text(active ? 'Deactivate' : 'Activate'),
                  ),
                  PopupMenuItem(
                    value: featured ? 'unfeature' : 'feature',
                    child: Text(featured ? 'Remove Featured' : 'Mark Featured'),
                  ),
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
      Map<String, dynamic> body = {};
      if (action == 'activate')
        body = {'isActive': true};
      else if (action == 'deactivate')
        body = {'isActive': false};
      else if (action == 'feature') {
        body = {
          'isFeatured': true,
          'featuredUntil': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30)),
          ),
        };
      } else if (action == 'unfeature')
        body = {'isFeatured': false, 'featuredUntil': null};

      await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/products/$id'),
        headers: {
          'Content-Type': 'application/json',
          'x-admin-secret': 'soko123',
        },
        body: jsonEncode(body),
      );
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Product updated: $action')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ============================================================
  // ORDERS TAB
  // ============================================================
  Widget _buildOrdersTab() {
    if (_loadingOrders) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final o = _orders[i];
          final id = o['id'] ?? '';
          final status = o['status'] ?? 'pending';
          final total = o['totalAmount'] ?? o['productPrice'] ?? 0;
          final buyer = o['buyerName'] ?? 'Unknown';
          final items = o['items'] as List?;
          final itemNames = items != null
              ? items.map((it) => it['name'] ?? '').join(', ')
              : o['productName'] ?? '';
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: ListTile(
              title: Text(
                '#${id.toString().substring(0, 8)} — $buyer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('$itemNames — TZS $total'),
              trailing: DropdownButton<String>(
                value: status,
                items:
                    [
                          'pending',
                          'confirmed',
                          'processing',
                          'shipped',
                          'delivered',
                          'cancelled',
                        ]
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                onChanged: (v) {
                  if (v != null) _updateOrder(id, v);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateOrder(String id, String status) async {
    try {
      await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/orders/$id'),
        headers: {
          'Content-Type': 'application/json',
          'x-admin-secret': 'soko123',
        },
        body: jsonEncode({'status': status}),
      );
      _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Order updated to $status')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ============================================================
  // STATS TAB
  // ============================================================
  Widget _buildStatsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Platform Earnings',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statCard(
                'Total Earnings',
                'TZS ${(_stats['totalEarnings'] ?? 0).toStringAsFixed(0)}',
                Icons.account_balance,
                Colors.green,
              ),
              const SizedBox(width: 12),
              _statCard(
                'Today',
                'TZS ${(_stats['todayEarnings'] ?? 0).toStringAsFixed(0)}',
                Icons.today,
                Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCard(
                'This Month',
                'TZS ${(_stats['monthlyEarnings'] ?? 0).toStringAsFixed(0)}',
                Icons.date_range,
                Colors.orange,
              ),
              const SizedBox(width: 12),
              _statCard(
                'Transactions',
                '${(_stats['totalTransactions'] ?? 0).toInt()}',
                Icons.receipt_long,
                Colors.purple,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Revenue Breakdown',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _revenueRow(
                    '2% Platform Commission',
                    'TZS ${(_stats['totalEarnings'] ?? 0).toStringAsFixed(0)}',
                    Colors.blueGrey,
                  ),
                  const Divider(),
                  _revenueRow('Subscription Income', 'TZS 0', Colors.amber),
                  const Divider(),
                  _revenueRow('Active Users', '${_users.length}', Colors.green),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _revenueRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
