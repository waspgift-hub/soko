import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../services/analytics_service.dart';
import '../../models/analytics_models.dart';
import '../../services/api_config.dart';
import '../../services/fraud_prevention_service.dart';
import '../../providers/product_feed_provider.dart';
import '../../widgets/google_loading.dart';
import '../report/admin_reports_screen.dart';
import 'admin_wallet_screen.dart';
import 'admin_ads_management_screen.dart';
import 'admin_transactions_tab.dart';
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
  // ignore: unused_field
  Map<String, int> _fraudStats = {};

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _products = [];
  bool _loadingUsers = false, _loadingProducts = false;
  String _userSearchQuery = '';

  List<Map<String, dynamic>> _disputedTxs = [];
  List<Map<String, dynamic>> _failedPayoutTxs = [];
  List<Map<String, dynamic>> _pendingKycUsers = [];
  bool _loadingExceptions = true;
  bool _loadingKyc = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 10, vsync: this);
    _checkAdmin();
    _loadFraudStats();
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
        ).showSnackBar(SnackBar(content: Text(context.tr('not_logged_in'))));
      }
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    final isAdminEmail = user.email?.toLowerCase() == 'admin@soko-langu.com' ||
        user.email?.toLowerCase() == 'admin@soko-vibe.com';
    if (data?['isAdmin'] != true && !isAdminEmail) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('access_denied'))));
      }
      return;
    }
    // Auto-fix Firestore isAdmin field for admin emails
    if (isAdminEmail && data?['isAdmin'] != true) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'isAdmin': true},
        SetOptions(merge: true),
      );
    }
    setState(() => _isAdmin = true);
    try {
      await Future.wait([
        _loadAnalytics(),
        _loadUsers(),
        _loadProducts(),
        _loadFraudStats(),
        _loadExceptions(),
      ]);
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
        setState(
          () => _users = snap.docs
              .map((d) => {'uid': d.id, ...d.data()})
              .toList(),
        );
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

  Future<void> _loadExceptions() async {
    setState(() => _loadingExceptions = true);
    try {
      final futures = <Future>[
        FirebaseFirestore.instance
            .collection('transactions')
            .where('status', isEqualTo: 'disputed')
            .get(),
        FirebaseFirestore.instance
            .collection('transactions')
            .where('payoutStatus', isEqualTo: 'failed_retry')
            .get(),
      ];

      // Try loading KYC pending from server
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        futures.add(_loadPendingKyc());
      }

      final results = await Future.wait(futures);
      final disputedSnap = results[0] as QuerySnapshot;
      final failedSnap = results[1] as QuerySnapshot;

      if (mounted) {
        setState(() {
          _disputedTxs = disputedSnap.docs
              .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
              .toList();
          _failedPayoutTxs = failedSnap.docs
              .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Admin loadExceptions: $e');
    }
    if (mounted) setState(() => _loadingExceptions = false);
  }

  Future<void> _loadPendingKyc() async {
    setState(() => _loadingKyc = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/pending'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final pending = body['pending'] as List? ?? [];
        if (mounted) {
          setState(
            () => _pendingKycUsers = pending.cast<Map<String, dynamic>>(),
          );
        }
      }
    } catch (e) {
      debugPrint('Admin loadPendingKyc: $e');
    }
    if (mounted) setState(() => _loadingKyc = false);
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('products')
          .get();
      if (mounted) {
        setState(
          () => _products = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList(),
        );
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
              Future.wait([
                _loadAnalytics(),
                _loadUsers(),
                _loadProducts(),
                _loadFraudStats(),
                _loadExceptions(),
              ]).then((_) => setState(() => _loading = false));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard),
              text: context.tr('dashboard'),
            ),
            Tab(
              icon: const Icon(Icons.analytics),
              text: context.tr('analytics'),
            ),
            Tab(icon: const Icon(Icons.people), text: context.tr('users')),
            Tab(
              icon: const Icon(Icons.inventory_2),
              text: context.tr('products'),
            ),
            Tab(icon: const Icon(Icons.ads_click), text: context.tr('ads')),
            Tab(icon: const Icon(Icons.flag), text: context.tr('reports')),
            Tab(icon: const Icon(Icons.security), text: context.tr('fraud')),
            Tab(icon: const Icon(Icons.payments), text: context.tr('payout')),
            Tab(
              icon: const Icon(Icons.receipt_long),
              text: context.tr('transactions'),
            ),
            const Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chats'),
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
            _buildAdsTab(),
            _buildReportsTab(),
            _buildFraudTab(),
            _buildPayoutTab(),
            _buildTransactionsTab(),
            _buildChatsTab(),
          ],
        ),
      ),
    );
  }

  // ─── DASHBOARD TAB — Exception-based management view ─────────
  Widget _buildDashboardTab() {
    if (_loadingExceptions) return const GoogleLoadingPage();
    final cs = Theme.of(context).colorScheme;
    final disputeCount = _disputedTxs.length;
    final failedCount = _failedPayoutTxs.length;
    final kycCount = _pendingKycUsers.length;
    final totalExceptions = disputeCount + failedCount + kycCount;

    return RefreshIndicator(
      onRefresh: _loadExceptions,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Summary cards row
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _exceptionSummaryCard(
                  icon: Icons.gavel,
                  count: disputeCount,
                  label: context.tr('disputes'),
                  color: Colors.orange,
                ),
                const SizedBox(width: 10),
                _exceptionSummaryCard(
                  icon: Icons.error_outline,
                  count: failedCount,
                  label: context.tr('failed_payouts'),
                  color: Colors.red,
                ),
                const SizedBox(width: 10),
                _exceptionSummaryCard(
                  icon: Icons.verified_user,
                  count: kycCount,
                  label: context.tr('pending_kyc'),
                  color: Colors.blue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (totalExceptions == 0)
            _buildEmptyExceptions(cs)
          else ...[
            // Disputed transactions
            if (disputeCount > 0) ...[
              _buildSectionHeader(
                '${context.tr('disputes')} ($disputeCount)',
                cs,
              ),
              const SizedBox(height: 8),
              ..._disputedTxs.map((tx) => _buildDisputeCard(tx, cs)),
              const SizedBox(height: 16),
            ],

            // Failed payouts
            if (failedCount > 0) ...[
              _buildSectionHeader(
                '${context.tr('failed_payouts')} ($failedCount)',
                cs,
              ),
              const SizedBox(height: 8),
              ..._failedPayoutTxs.map((tx) => _buildFailedPayoutCard(tx, cs)),
              const SizedBox(height: 16),
            ],

            // Pending KYC
            if (kycCount > 0) ...[
              _buildSectionHeader(
                '${context.tr('pending_kyc')} ($kycCount)',
                cs,
              ),
              const SizedBox(height: 8),
              if (_loadingKyc)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ..._pendingKycUsers.map((u) => _buildKycCard(u, cs)),
              const SizedBox(height: 16),
            ],
          ],

          // Quick actions always visible
          _buildSectionHeader(context.tr('quick_actions'), cs),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _exceptionSummaryCard({
    required IconData icon,
    required int count,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.71),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyExceptions(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Colors.green.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Hakuna matatizo yanayohitaji umakini',
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Kila kitu kiko sawa!',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisputeCard(Map<String, dynamic> tx, ColorScheme cs) {
    final nf = NumberFormat('#,###', 'en');
    final dateStr = _formatTimestamp(tx['createdAt']);
    final productName = tx['productName'] ?? 'Bidhaa';
    final price = (tx['productPrice'] ?? 0).toDouble();
    final buyerName = tx['buyerName'] ?? tx['buyerId'] ?? '---';
    final sellerName = tx['sellerName'] ?? tx['sellerId'] ?? '---';
    final reason = tx['disputeInfo']?['reason'] ?? '---';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gavel, size: 18, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  'TZS ${nf.format(price.toInt())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Mnunuzi: $buyerName  |  Muuzaji: $sellerName',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              'Sababu: $reason',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.gavel, size: 16),
                label: Text(context.tr('resolve_dispute')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _showResolveDisputeDialog(tx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedPayoutCard(Map<String, dynamic> tx, ColorScheme cs) {
    final nf = NumberFormat('#,###', 'en');
    final dateStr = _formatTimestamp(tx['payoutFailedAt'] ?? tx['createdAt']);
    final productName = tx['productName'] ?? 'Bidhaa';
    final price = (tx['productPrice'] ?? 0).toDouble();
    final sellerName = tx['sellerName'] ?? tx['sellerId'] ?? '---';
    final error = tx['payoutError'] ?? 'Unknown error';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  'TZS ${nf.format(price.toInt())}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Muuzaji: $sellerName',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              'Hitilafu: $error',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(context.tr('retry_payout')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _retryPayout(tx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKycCard(Map<String, dynamic> user, ColorScheme cs) {
    final kyc = user['kyc'] as Map<String, dynamic>? ?? {};
    final dateStr = _formatTimestamp(kyc['submittedAt']);
    final fullName = kyc['fullName'] ?? user['displayName'] ?? '---';
    final email = user['email'] ?? '---';
    final phone = user['phone'] ?? '---';
    final idType = kyc['idType'] ?? '---';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, size: 18, color: Colors.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  idType,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              email,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              phone,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.rate_review, size: 16),
                label: Text(context.tr('review_kyc')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _showKycReviewDialog(user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '---';
    try {
      if (ts is Timestamp) {
        return DateFormat('MMM dd, HH:mm').format(ts.toDate());
      }
      return ts.toString();
    } catch (_) {
      return '---';
    }
  }

  Widget _buildSectionHeader(String title, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  // ─── BAR CHART ───────────────────────────────────────────
  Widget _buildBarChart(
    List<BarEntry> entries,
    Color color,
    String Function(double) format,
  ) {
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
          final dayLabels = [
            context.tr('mon'),
            context.tr('tue'),
            context.tr('wed'),
            context.tr('thu'),
            context.tr('fri'),
            context.tr('sat'),
            context.tr('sun'),
          ];
          final dayLabel = dayLabels[e.date.weekday - 1];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    format(e.value),
                    style: TextStyle(
                      fontSize: 9,
                      color: color.withValues(alpha: 0.71),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
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
                  Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
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
        _actionTile(
          Icons.account_balance_wallet,
          context.tr('wallet'),
          Theme.of(context).colorScheme.secondary,
          () => context.push(AppRoutes.adminWallet),
        ),
        _actionTile(
          Icons.notifications,
          context.tr('send_notification'),
          Theme.of(context).colorScheme.tertiary,
          _showSendNotificationDialog,
        ),
        _actionTile(
          Icons.download,
          context.tr('export_users'),
          Theme.of(context).colorScheme.primary,
          _exportUsersCsv,
        ),
        _actionTile(
          Icons.analytics,
          'Analytics za App',
          Theme.of(context).colorScheme.primary,
          () => context.push(AppRoutes.sellerAnalytics, extra: '__all__'),
        ),
        _actionTile(
          Icons.settings,
          context.tr('maintenance'),
          Theme.of(context).colorScheme.error,
          _toggleMaintenance,
        ),
      ],
    );
  }

  Widget _actionTile(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
              decoration: InputDecoration(
                labelText: context.tr('title'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.tr('body'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              await _analyticsService.sendPushToAll(
                titleCtrl.text,
                bodyCtrl.text,
              );
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
        const SnackBar(
          content: Text('Users CSV saved to admin_exports collection'),
        ),
      );
    }
  }

  // ─── TOGGLE MAINTENANCE ───────────────────────────────
  Future<void> _toggleMaintenance() async {
    final currentlyEnabled = await _analyticsService.getMaintenanceMode();
    final messageCtrl = TextEditingController(
      text: currentlyEnabled ? '' : 'App iko kwenye matengenezo. Tafadhali rudi baadaye.',
    );
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('maintenance')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Hali ya sasa: ',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: currentlyEnabled
                        ? Colors.red.withValues(alpha: 0.12)
                        : Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    currentlyEnabled ? 'IMEWASHWA' : 'IMEZIMWA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: currentlyEnabled ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Ujumbe kwa watumiaji',
                hintText: 'App iko kwenye matengenezo...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Hutaweza kufikia app wakati maintenance ikiwa washwa. Watumiaji wote (isipokuwa admin) watazuiwa.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            icon: Icon(currentlyEnabled ? Icons.power_settings_new : Icons.warning_amber),
            label: Text(currentlyEnabled ? 'Zima Maintenance' : 'Washa Maintenance'),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyEnabled ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, {
              'enable': !currentlyEnabled,
              'message': messageCtrl.text.trim(),
            }),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await _analyticsService.toggleMaintenanceMode(
      result['enable'] as bool,
      message: result['message'] as String?,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['enable'] as bool
                ? 'Maintenance imewashwa'
                : 'Maintenance imezimwa',
          ),
        ),
      );
    }
  }

  // ─── ACTION: Resolve Dispute ───────────────────────────────
  void _showResolveDisputeDialog(Map<String, dynamic> tx) {
    final orderId = tx['id'] as String;
    final productName = tx['productName'] ?? 'Bidhaa';
    final nf = NumberFormat('#,###', 'en');
    final price = (tx['productPrice'] ?? 0).toDouble();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('resolve_dispute')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$productName — TZS ${nf.format(price.toInt())}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${context.tr('reason')}: ${tx['disputeInfo']?['reason'] ?? '---'}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('admin_note'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('choose_resolution'),
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.person, size: 16),
            label: Text(context.tr('release_to_seller')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _resolveDispute(orderId, 'release', noteCtrl.text);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.replay, size: 16),
            label: Text(context.tr('refund_to_buyer')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _resolveDispute(orderId, 'refund', noteCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _resolveDispute(
    String orderId,
    String resolution,
    String note,
  ) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/admin-resolve-dispute'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'orderId': orderId,
          'resolution': resolution,
          'note': note,
        }),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        _loadExceptions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? context.tr('dispute_resolved'),
              ),
            ),
          );
        }
      } else {
        throw Exception(result['error'] ?? 'Failed to resolve dispute');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ─── ACTION: Retry Failed Payout ───────────────────────────
  Future<void> _retryPayout(Map<String, dynamic> tx) async {
    final orderId = tx['id'] as String;
    final productName = tx['productName'] ?? 'Bidhaa';
    final nf = NumberFormat('#,###', 'en');
    final price = (tx['productPrice'] ?? 0).toDouble();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('retry_payout')),
        content: Text(
          context
              .tr('retry_payout_confirm')
              .replaceAll(
                '{product}',
                '$productName (TZS ${nf.format(price.toInt())})',
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('retry')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/retry-payout'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'orderId': orderId}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        _loadExceptions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? context.tr('payout_retried')),
            ),
          );
        }
      } else {
        throw Exception(result['error'] ?? context.tr('retry_failed'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ─── ACTION: Review KYC ─────────────────────────────────────
  void _showKycReviewDialog(Map<String, dynamic> user) {
    final uid = user['uid'] as String;
    final kyc = user['kyc'] as Map<String, dynamic>? ?? {};
    final fullName = kyc['fullName'] ?? user['displayName'] ?? '---';
    final idType = kyc['idType'] ?? '---';
    final idNumber = kyc['idNumber'] ?? '---';
    final idImageUrl = kyc['idImageUrl'] as String?;
    final selfieUrl = kyc['selfieUrl'] as String?;
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('review_kyc')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Jina: $fullName',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('Aina ya Kitambulisho: $idType'),
              Text('Namba: $idNumber'),
              if (idImageUrl != null) ...[
                const SizedBox(height: 8),
                Text('Kitambulisho:'),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    idImageUrl,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                  ),
                ),
              ],
              if (selfieUrl != null) ...[
                const SizedBox(height: 8),
                Text('Selfie:'),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    selfieUrl,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Maelezo (sababu ya kukataa)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: Text(context.tr('reject')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _submitKycReview(uid, false, notesCtrl.text);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: Text(context.tr('approve')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _submitKycReview(uid, true, notesCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submitKycReview(String uid, bool approve, String notes) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/kyc/review'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': uid, 'approve': approve, 'notes': notes}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        _loadExceptions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ??
                    context
                        .tr('kyc_status')
                        .replaceAll(
                          '{status}',
                          approve ? 'approved' : 'rejected',
                        ),
              ),
            ),
          );
        }
      } else {
        throw Exception(result['error'] ?? context.tr('kyc_review_failed'));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ─── ANALYTICS TAB ───────────────────────────────────────
  Widget _buildAnalyticsTab() {
    final a = _analytics ?? AnalyticsData();
    final nf = NumberFormat('#,###', 'en');
    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr('user_analytics'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _statRow(
            context.tr('total_users'),
            '${a.totalUsers}',
            '${context.tr('new_today')} ${a.newUsersToday}',
            '${context.tr('new_month')} ${a.newUsersThisMonth}',
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('product_analytics'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _statRow(
            context.tr('total_products'),
            '${a.totalProducts}',
            '${context.tr('active_label')} ${a.activeProducts}',
            '${context.tr('inactive_label')} ${a.inactiveProducts}',
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('orders'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _statRow(
            context.tr('total_orders'),
            nf.format(a.totalOrders),
            '', '',
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('revenue'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _statRow(
            context.tr('total_revenue'),
            'TZS ${a.totalRevenue.toStringAsFixed(0)}',
            'Today: TZS ${a.revenueToday.toStringAsFixed(0)}',
            'Month: TZS ${a.revenueThisMonth.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('category_distribution'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildCategoryList(a.productsByCategory, a.totalProducts),
          const SizedBox(height: 20),
          Text(
            context.tr('revenue_trend_7_days'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildBarChart(
            a.revenueOverTime
                .map((m) => BarEntry(m.date, m.count.toDouble()))
                .toList(),
            Theme.of(context).colorScheme.primary,
            (v) => 'TZS $v',
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('new_users_7_days'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildBarChart(
            a.userGrowth
                .map((m) => BarEntry(m.date, m.count.toDouble()))
                .toList(),
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
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mainValue,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
    if (catMap.isEmpty)
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr('no_products')),
        ),
      );
    final sorted = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
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
                  SizedBox(
                    width: 120,
                    child: Text(
                      e.key,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / total,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.12),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
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
            decoration: InputDecoration(
              hintText: context.tr('search_users'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (q) =>
                setState(() => _userSearchQuery = q.toLowerCase()),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadUsers,
            child: ListView.builder(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 8,
              ),
              itemCount: _users.where((u) {
                final name = (u['displayName'] ?? u['email'] ?? '')
                    .toString()
                    .toLowerCase();
                final phone = (u['phone'] ?? '').toString().toLowerCase();
                return name.contains(_userSearchQuery) ||
                    phone.contains(_userSearchQuery);
              }).length,
              itemBuilder: (_, i) {
                final filtered = _users.where((u) {
                  final name = (u['displayName'] ?? u['email'] ?? '')
                      .toString()
                      .toLowerCase();
                  final phone = (u['phone'] ?? '').toString().toLowerCase();
                  return name.contains(_userSearchQuery) ||
                      phone.contains(_userSearchQuery);
                }).toList();
                final u = filtered[i];
                final name =
                    u['displayName'] ?? u['email'] ?? context.tr('unknown');
                final suspended = u['isSuspended'] == true;
                final phone = u['phone'] ?? '';
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: suspended
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      child: Text(
                        name.toString()[0].toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ),
                    title: Text('$name${suspended ? ' (Suspended)' : ''}'),
                    subtitle: Text(phone),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => _updateUser(u['uid'] as String, v),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'toggle_admin',
                          child: Text(context.tr('toggle_admin')),
                        ),
                        PopupMenuItem(
                          value: suspended ? 'unsuspend' : 'suspend',
                          child: Text(
                            suspended
                                ? context.tr('unsuspend')
                                : context.tr('suspend'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'full_delete',
                          child: Text(
                            context.tr('full_delete'),
                            style: const TextStyle(color: Colors.red),
                          ),
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
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final authHeaders = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      if (action == 'full_delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('delete_user_forever')),
            content: Text(context.tr('delete_user_forever_confirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  context.tr('delete_forever'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        final resp = await http.delete(
          Uri.parse('${ApiConfig.baseUrl}/api/admin/users/$uid/full-delete'),
          headers: authHeaders,
        );
        if (resp.statusCode != 200) {
          throw Exception(
            jsonDecode(resp.body)['error'] ?? context.tr('error'),
          );
        }
        _loadUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('user_permanently_deleted'))),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('user_updated').replaceAll('{action}', action),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
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
                  width: 48,
                  height: 48,
                  color: Theme.of(context).colorScheme.outlineVariant,
                  child: p['images'] != null && (p['images'] as List).isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: (p['images'] as List).first,
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          Icons.image,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                ),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '$seller — TZS $price${!active ? context.tr('hidden') : ''}${featured ? ' ⭐' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _updateProduct(p['id'] as String, v),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: active ? 'deactivate' : 'activate',
                    child: Text(
                      active
                          ? context.tr('deactivate')
                          : context.tr('activate'),
                    ),
                  ),
                  PopupMenuItem(
                    value: featured ? 'unfeature' : 'feature',
                    child: Text(
                      featured
                          ? context.tr('remove_featured')
                          : context.tr('mark_featured'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      context.tr('delete'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
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
      if (action == 'delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('delete_product')),
            content: Text(context.tr('delete_confirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  context.tr('delete'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
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
            throw Exception(result['error'] ?? context.tr('error'));
          }
          if (mounted) {
            context.read<ProductFeedProvider>().removeProduct(id);
          }
        } catch (e) {
          throw Exception(e.toString());
        }
        _loadProducts();
        return;
      }
      Map<String, dynamic> body = {};
      if (action == 'activate') {
        body = {'isActive': true};
      } else if (action == 'deactivate') {
        body = {'isActive': false};
      } else if (action == 'feature') {
        body = {
          'isFeatured': true,
          'featuredUntil': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30)),
          ),
        };
      } else if (action == 'unfeature') {
        body = {'isFeatured': false, 'featuredUntil': null};
      }
      await FirebaseFirestore.instance
          .collection('products')
          .doc(id)
          .update(body);
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('product_updated').replaceAll('{action}', action),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  // ─── ADS MANAGEMENT TAB ─────────────────────────────────────
  Widget _buildAdsTab() {
    return const AdminAdsManagementScreen(embedded: true);
  }

  // ─── REPORTS TAB ─────────────────────────────────────────────
  Widget _buildReportsTab() {
    return const AdminReportsScreen(embedded: true);
  }

  // ─── PAYOUT TAB ───────────────────────────────────────────────
  Widget _buildTransactionsTab() {
    return const AdminTransactionsTab();
  }

  Widget _buildPayoutTab() {
    return const AdminWalletScreen(embedded: true);
  }

  Widget _buildChatsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chat_rooms')
          .orderBy('last_timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const GoogleLoadingPage();
        }
        if (snap.hasError) {
          return Center(child: Text('Failed: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Hakuna chat rooms bado',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final isAi = data['is_ai_dalali_room'] == true;
            final participants = List<String>.from(data['participants'] ?? []);
            final buyerId = data['buyer_id'] ?? '-';
            final sellerId = data['seller_id'] ?? '-';
            final productTitle = data['product_title'] as String?;
            final unreadBuyer = data['unread_count_buyer'] ?? 0;
            final unreadSeller = data['unread_count_seller'] ?? 0;
            final lastMessage = data['last_message']?.toString() ?? '';
            final ts = data['last_timestamp'];
            final date = ts is Timestamp
                ? DateFormat('dd/MM HH:mm').format(ts.toDate())
                : '-';
            return Card(
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: isAi
                      ? Colors.teal.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(isAi ? Icons.smart_toy : Icons.chat),
                ),
                title: Text(
                  isAi ? 'Soko Vibe AI Dalali' : doc.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  lastMessage.isEmpty ? 'No messages' : lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(date, style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      'B:$unreadBuyer S:$unreadSeller',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  _adminDetailRow('Buyer', buyerId.toString()),
                  _adminDetailRow('Seller/AI', sellerId.toString()),
                  _adminDetailRow('Participants', participants.join(', ')),
                  if (productTitle?.isNotEmpty == true)
                    _adminDetailRow('Product', productTitle!),
                  _adminDetailRow('Room ID', doc.id),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _adminDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  // ─── FRAUD TAB ────────────────────────────────────────────────
  Widget _buildFraudTab() {
    return Column(
      children: [
        if (_fraudStats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _fraudStatChip(context.tr('total'), _fraudStats['total'] ?? 0),
                _fraudStatChip(
                  context.tr('open'),
                  _fraudStats['unresolved'] ?? 0,
                ),
                _fraudStatChip(
                  context.tr('high'),
                  _fraudStats['high'] ?? 0,
                  isHigh: true,
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<FraudAlert>>(
            stream: _fraudService.getFraudAlerts(resolved: false),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const GoogleLoadingPage();
              final alerts = snap.data ?? [];
              if (alerts.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.security,
                          size: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('no_active_fraud_alerts'),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),

                        Text(
                          context
                              .tr('test_mode_status')
                              .replaceAll(
                                '{status}',
                                _fraudService.isTestMode ? 'ON' : 'OFF',
                              ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
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
          ),
        ),
      ],
    );
  }

  Widget _fraudStatChip(String label, int value, {bool isHigh = false}) {
    final cs = Theme.of(context).colorScheme;
    final color = isHigh ? cs.error : cs.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
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
        title: Text(
          alert.sellerName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '${alert.description}\n$dateStr',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: TextButton(
          onPressed: () => _fraudService.markResolved(alert.id),
          child: Text(context.tr('dismiss'), style: TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
