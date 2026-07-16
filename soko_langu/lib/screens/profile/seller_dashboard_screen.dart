import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/product_service.dart';
import '../../services/payment_service.dart';
import '../../extensions/context_tr.dart';
import '../../models/product_model.dart';
import '../../models/transaction_model.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../utils/phone_utils.dart';
import '../../models/flash_sale_model.dart';
import '../../services/flash_sale_service.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/glass_container.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
            colors: [cs.primary.withValues(alpha: 0.04), cs.surface],
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
                  return RefreshIndicator(
                    onRefresh: () async => setState(() {}),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
                      children: [
                        // Stats row with glass cards
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Expanded(child: _glassStatCard(cs, Icons.inventory_2, productCount.toString(), context.tr('total_products'), cs.secondary)),
                              const SizedBox(width: 12),
                              Expanded(child: _glassStatCard(cs, Icons.receipt_long, '$txCount ${context.tr('sold')}', context.tr('total_sales'), cs.tertiary)),
                            ],
                          ),
                        ),
                        _buildEarningsCard(),
                        const SizedBox(height: 14),
                        _buildQuickActions(cs, isDark, productSnap.data ?? []),
                        if (user?.email == 'admin@soko-langu.com' || _isAdmin) ...[
                          const SizedBox(height: 14),
                          _buildAdminSection(),
                        ],
                        if (completedTx.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(context.tr('tx_history'),
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface)),
                          const SizedBox(height: 10),
                          ...completedTx.take(10).map((tx) => _buildTransactionTile(tx)),
                        ] else ...[
                          const SizedBox(height: 20),
                          Center(
                            child: Text(context.tr('no_transactions'),
                              style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                        ],
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

  Widget _glassStatCard(ColorScheme cs, IconData icon, String value, String label, Color color) {
    return GlassContainer(
      blur: 20,
      opacity: 0.1,
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
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
    return GlassContainer(
      blur: 24,
      opacity: isDark ? 0.08 : 0.05,
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vitendo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _actionButton(cs, Icons.price_check, 'Toa\nNafasi', () => context.push(AppRoutes.sellerQuote), cs.primary)),
              const SizedBox(width: 8),
              Expanded(child: _actionButton(cs, Icons.local_shipping, 'Tuma\nBidhaa', () => context.push(AppRoutes.sellerDispatch), Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _actionButton(cs, Icons.store, 'Customize\nShop', () => context.push(AppRoutes.shopCustomization), cs.primary)),
              const SizedBox(width: 8),
              Expanded(child: _actionButton(cs, Icons.verified, 'Boost\nListing', () => _showBoostDialog(products), cs.trendingOrange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(ColorScheme cs, IconData icon, String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: cs.onSurface, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    BuildContext context,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
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
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(MarketplaceTransaction tx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tx.status == TransactionStatus.delivered || tx.status == TransactionStatus.completed
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : tx.status == TransactionStatus.escrowHold
                  ? Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          child: Icon(
            tx.status == TransactionStatus.delivered || tx.status == TransactionStatus.completed
                ? Icons.check_circle
                : tx.status == TransactionStatus.escrowHold
                    ? Icons.lock
                    : Icons.pending,
            color: tx.status == TransactionStatus.delivered || tx.status == TransactionStatus.completed
                ? Theme.of(context).colorScheme.primary
                : tx.status == TransactionStatus.escrowHold
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          tx.productName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tx.buyerName} - TZS ${tx.sellerReceives.toStringAsFixed(0)}'),
            if (tx.buyerPhone.isNotEmpty)
              Text(
                PhoneUtils.formatForDisplay(tx.buyerPhone),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'TZS ${tx.totalAmount.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSection() {
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
            Text(
              context.tr('admin_platform_earnings'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _statCard(
                  context,
                  Icons.account_balance,
                  '\$${(stats['totalEarnings'] ?? 0).toStringAsFixed(2)}',
                  context.tr('platform_commission_2'),
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                _statCard(
                  context,
                  Icons.trending_up,
                  '\$${(stats['todayEarnings'] ?? 0).toStringAsFixed(2)}',
                  context.tr('today'),
                  Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        );
      },
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
              borderRadius: BorderRadius.circular(22),
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
                      child: Icon(Icons.account_balance_wallet, color: cs.surface, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(context.tr('seller_earnings'),
                        style: TextStyle(color: cs.surface, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                    Icon(Icons.arrow_forward_ios, color: cs.surface.withValues(alpha: 0.7), size: 16),
                  ],
                ),
                const SizedBox(height: 16),
                Text('TZS ${nf.format(balance)}',
                  style: TextStyle(color: cs.surface, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
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

  Widget _buildKycCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final kyc = snap.data?.data() as Map<String, dynamic>?;
        final kycData = kyc?['kyc'] as Map<String, dynamic>?;
        final kycStatus = kycData?['status'] as String? ?? 'none';

        String title;
        String subtitle;
        Color color;
        IconData icon;

        switch (kycStatus) {
          case 'approved':
            title = context.tr('kyc_approved');
            subtitle = context.tr('can_sell_products');
            color = cs.primary;
            icon = Icons.verified;
            break;
          case 'pending':
            title = context.tr('kyc_pending');
            subtitle = context.tr('kyc_pending_subtitle');
            color = cs.tertiary;
            icon = Icons.hourglass_top;
            break;
          case 'rejected':
            title = context.tr('kyc_rejected');
            subtitle = context.tr('kyc_rejected_subtitle');
            color = cs.error;
            icon = Icons.cancel;
            break;
          default:
            title = context.tr('kyc_not_submitted');
            subtitle = context.tr('verify_id_to_sell');
            color = cs.onSurface.withValues(alpha: 0.6);
            icon = Icons.verified_outlined;
        }

        return GestureDetector(
          onTap: () => context.push(AppRoutes.kyc),
          child: GlassContainer(
            blur: 20,
            opacity: 0.08,
            borderRadius: 18,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: color, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayoutPrefsCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final autoPayout = data?['autoPayout'] as bool? ?? true;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('auto_payout'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      autoPayout ? context.tr('auto_payout') : context.tr('manual_payout'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: autoPayout,
                onChanged: (val) async {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({'autoPayout': val});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuoteButton() {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.sellerQuote),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.price_check, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Toa Gharama ya Usafirishaji',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Weka gharama ya usafirishaji kwa ombi la mnunuzi',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDispatchButton() {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.sellerDispatch),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.shade700, Colors.orange.shade500],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_shipping, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tuma Bidhaa',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Weka proof of delivery na tracking number',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomizeShopButton() {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.shopCustomization),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child:  Icon(Icons.store, color: Theme.of(context).colorScheme.surface, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('customize_shop'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.surface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('customize_shop_subtitle'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Theme.of(context).colorScheme.surface, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashSaleCard(List<Product> products) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<FlashSale>>(
      stream: FlashSaleService().getMyFlashSales(),
      builder: (context, snap) {
        final activeCount = snap.data?.length ?? 0;
        return GestureDetector(
          onTap: () {
            if (products.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('add_product_first'))),
              );
              return;
            }
            context.push(AppRoutes.createFlashSale);
          },
          child: GlassContainer(
            blur: 24,
            opacity: isDark ? 0.12 : 0.06,
            borderRadius: 22,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.local_fire_department, color: cs.error, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('unda_flash_sale'),
                        style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(activeCount > 0
                          ? context.tr('flash_sales_active').replaceFirst('{0}', '$activeCount')
                          : context.tr('create_flash_sale_prompt'),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: cs.onSurfaceVariant, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoostButton(List<Product> products) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: products.isEmpty ? null : () => _showBoostDialog(products),
      child: GlassContainer(
        blur: 24,
        opacity: isDark ? 0.12 : 0.06,
        borderRadius: 22,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.trendingOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.verified, color: cs.trendingOrange, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('boost_listing'),
                    style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(products.isEmpty ? context.tr('add_product_first') : context.tr('boost_plans'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: cs.onSurfaceVariant, size: 16),
          ],
        ),
      ),
    );
  }

  void _showBoostDialog(List<Product> products) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
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
                height: 200,
                child: ListView.separated(
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
        );
      },
    );
  }



}
