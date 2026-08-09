import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/product_service.dart';
import '../../services/payment_service.dart';
import '../../services/widget_service.dart';
import '../../services/balance_privacy_service.dart';
import '../../extensions/context_tr.dart';
import '../../models/product_model.dart';
import '../../models/transaction_model.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../utils/phone_utils.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/soko_vibe_states.dart';
import '../../widgets/ds/ds.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  final ProductService _productService = ProductService();
  final PaymentService _paymentService = PaymentService();
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _isAdmin = doc.data()?['isAdmin'] == true;
      });
    }
  }

  void _updateWidget(List<MarketplaceTransaction> transactions) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
      final data = doc.data();
      final balance = (data?['sellerBalance'] as num? ?? 0);
      final totalSales = (data?['totalSales'] as num? ?? 0);
      final nf = NumberFormat('#,###', 'en');
      final pendingCount = transactions.where(
        (t) => t.status == TransactionStatus.pending,
      ).length;
      WidgetService.updateWidget(
        sales: 'TZS ${nf.format(totalSales)}',
        orders: '$pendingCount',
        balance: 'TZS ${nf.format(balance)}',
      );
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('dashboard')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [isDark ? Colors.black : Colors.white, cs.surface],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<List<MarketplaceTransaction>>(
            stream: _paymentService.getSellerTransactions(),
            builder: (context, txSnap) {
              if (txSnap.hasError) {
                debugPrint('SellerDashboard tx error: ${txSnap.error}');
              }
              final transactions = txSnap.data ?? [];

              return StreamBuilder<List<Product>>(
                stream: _productService.getMyProducts(),
                builder: (context, productSnap) {
                  if (productSnap.hasError) {
                    debugPrint('SellerDashboard products error: ${productSnap.error}');
                  }
                  if (txSnap.connectionState == ConnectionState.waiting ||
                      productSnap.connectionState == ConnectionState.waiting) {
                    return const GoogleLoadingPage();
                  }
                  final productCount = productSnap.data?.length ?? 0;
                  final completedTx = transactions.where(
                    (t) => t.status == TransactionStatus.completed,
                  );
                  final txCount = completedTx.length;
                  _updateWidget(transactions);
                  return RefreshIndicator(
                    onRefresh: () async => setState(() {}),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
                      children: [
                        _buildStatsRow(cs, productCount, txCount),
                        const SizedBox(height: 16),
                        _buildEarningsCard(),
                        const SizedBox(height: 20),
                        _buildQuickActions(cs, isDark, productSnap.data ?? []),
                        if (user?.email == 'admin@soko-langu.com' || _isAdmin) ...[
                          const SizedBox(height: 20),
                          _buildAdminSection(),
                        ],
                        const SizedBox(height: 20),
                        _buildSectionTitle(context, cs, Icons.receipt_long_outlined, context.tr('tx_history')),
                        const SizedBox(height: 12),
                        if (completedTx.isNotEmpty)
                          ...completedTx.take(10).map((tx) => _buildTransactionTile(tx))
                        else
                          DsEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: context.tr('no_transactions'),
                            centered: false,
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, ColorScheme cs, IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _buildStatsRow(ColorScheme cs, int productCount, int txCount) {
    return Row(
      children: [
        Expanded(child: _statCard(cs, Icons.inventory_2_outlined, '$productCount', context.tr('total_products'), cs.secondary)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(cs, Icons.receipt_long_outlined, '$txCount ${context.tr('sold')}', context.tr('total_sales'), cs.tertiary)),
      ],
    );
  }

  Widget _statCard(ColorScheme cs, IconData icon, String value, String label, Color color) {
    return DsCard(
      onTap: null,
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ColorScheme cs, bool isDark, List<Product> products) {
    final actions = [
      _QuickActionData(Icons.add_business_outlined, context.tr('sell_product'), () => context.push(AppRoutes.addProduct), cs.primary),
      _QuickActionData(Icons.price_check_outlined, context.tr('give_quote'), () => context.push(AppRoutes.sellerQuote), cs.secondary),
      _QuickActionData(Icons.local_shipping_outlined, context.tr('dispatch_product'), () => context.push(AppRoutes.sellerDispatch), cs.trendingOrange),
      _QuickActionData(Icons.storefront_outlined, context.tr('customize_shop_action'), () => context.push(AppRoutes.shopCustomization), cs.primary),
      _QuickActionData(Icons.verified_outlined, context.tr('boost_listing_action'), () => _showBoostDialog(products), cs.trendingOrange),
      _QuickActionData(Icons.account_balance_outlined, context.tr('statement'), () => context.push(AppRoutes.sellerStatement), cs.premiumTeal),
      _QuickActionData(Icons.receipt_long_outlined, context.tr('order_history'), () => context.push(AppRoutes.sellerOrders), cs.tertiary),
      _QuickActionData(Icons.flash_on_outlined, context.tr('unda_flash_sale'), () => context.push(AppRoutes.createFlashSale), cs.trendingOrange),
      _QuickActionData(Icons.manage_search_outlined, context.tr('natufuta_bidhaa'), () => context.push(AppRoutes.buyerRequests), cs.secondary),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, cs, Icons.bolt_outlined, context.tr('actions_title')),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
          ),
          itemCount: actions.length,
          itemBuilder: (_, i) => _buildQuickActionTile(cs, isDark, actions[i]),
        ),
      ],
    );
  }

  Widget _buildQuickActionTile(ColorScheme cs, bool isDark, _QuickActionData a) {
    return DsCard(
      onTap: a.onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: a.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(a.icon, color: a.color, size: 24),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              a.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurface, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(MarketplaceTransaction tx) {
    final cs = Theme.of(context).colorScheme;
    final delivered = tx.status == TransactionStatus.delivered || tx.status == TransactionStatus.completed;
    final escrow = tx.status == TransactionStatus.escrowHold;
    final statusColor = delivered ? cs.successGreen : escrow ? cs.tertiary : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DsCard(
        radius: 18,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [statusColor, statusColor.withValues(alpha: 0.35)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          delivered
                              ? Icons.check_circle_rounded
                              : escrow
                                  ? Icons.lock_rounded
                                  : Icons.pending_outlined,
                          color: statusColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text('${tx.buyerName} · TZS ${tx.sellerReceives.toStringAsFixed(0)}',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (tx.buyerPhone.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(PhoneUtils.formatForDisplay(tx.buyerPhone),
                                    style: TextStyle(fontSize: 11, color: cs.primary)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('TZS ${tx.totalAmount.toStringAsFixed(0)}',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.primary)),
                          const SizedBox(height: 2),
                          Text('${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          if (tx.platformFee > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('Comm: -TZS ${tx.platformFee.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 10, color: cs.error)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminSection() {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, double>>(
      future: _paymentService.getRevenueStats(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const GoogleLoadingPage();
        }
        final stats = snap.data ?? {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, cs, Icons.admin_panel_settings_outlined, context.tr('admin_platform_earnings')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _adminStatCard(
                    cs,
                    Icons.account_balance_outlined,
                    '\$${(stats['totalEarnings'] ?? 0).toStringAsFixed(2)}',
                    context.tr('platform_commission_2'),
                    cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _adminStatCard(
                    cs,
                    Icons.trending_up,
                    '\$${(stats['todayEarnings'] ?? 0).toStringAsFixed(2)}',
                    context.tr('today'),
                    cs.primary,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _adminStatCard(ColorScheme cs, IconData icon, String value, String label, Color color) {
    return DsCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEarningsCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final balance = (snap.data?.data() as Map<String, dynamic>?)?['sellerBalance'] as num? ?? 0;
        final totalSales = (snap.data?.data() as Map<String, dynamic>?)?['totalSales'] as num? ?? 0;
        final nf = NumberFormat('#,###', 'en');
        return GestureDetector(
          onTap: () => context.push(AppRoutes.sellerEarnings),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.primary.withValues(alpha: 0.75)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.account_balance_wallet_rounded, color: cs.surface, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(context.tr('seller_earnings'),
                        style: TextStyle(color: cs.surface, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                    Consumer<BalancePrivacyService>(
                      builder: (ctx, privacy, _) => GestureDetector(
                        onTap: privacy.toggle,
                        child: Icon(
                          privacy.hideBalances ? Icons.visibility_off : Icons.visibility,
                          color: cs.surface.withValues(alpha: 0.7), size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, color: cs.surface.withValues(alpha: 0.7), size: 16),
                  ],
                ),
                const SizedBox(height: 16),
                Consumer<BalancePrivacyService>(
                  builder: (ctx, privacy, _) => Text(
                    privacy.hideBalances ? 'TZS ****' : 'TZS ${nf.format(balance)}',
                    style: TextStyle(color: cs.surface, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
                ),
                const SizedBox(height: 4),
                Text(context.tr('seller_earnings_subtitle').replaceFirst('{0}', '$totalSales'),
                  style: TextStyle(color: cs.surface.withValues(alpha: 0.8), fontSize: 13)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBoostDialog(List<Product> products) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DsSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('boost_dialog_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('choose_product_boost'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: products.isEmpty
                  ? SokoVibeEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: context.tr('no_products'),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final p = products[i];
                        final alreadyBoosted = p.isBoostedValid;
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 48,
                              height: 48,
                              color: Theme.of(context).colorScheme.outlineVariant,
                              child: p.images.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: p.images.first, fit: BoxFit.cover)
                                  : Icon(Icons.image, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            alreadyBoosted ? context.tr('already_featured') : context.tr('tap_to_boost'),
                          ),
                          trailing: alreadyBoosted
                              ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                              : const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: alreadyBoosted
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  context.push(AppRoutes.productBoost, extra: p);
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionData {
  const _QuickActionData(this.icon, this.label, this.onTap, this.color);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
}
