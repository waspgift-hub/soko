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
import '../../models/flash_sale_model.dart';
import '../../services/flash_sale_service.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  final ProductService _productService = ProductService();
  final PaymentService _paymentService = PaymentService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('dashboard'))),
      body: SafeArea(
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + MediaQuery.of(context).padding.bottom,
                    ),
                    children: [
                      Row(
                        children: [
                          _statCard(
                            context,
                            Icons.inventory_2,
                            productCount.toString(),
                            context.tr('total_products'),
                            Colors.blue,
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            context,
                            Icons.receipt_long,
                            '$txCount Sold',
                            context.tr('total_sales'),
                            Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildEarningsCard(),
                      const SizedBox(height: 16),
                      _buildKycCard(),
                      const SizedBox(height: 16),
                      _buildCustomizeShopButton(),
                      const SizedBox(height: 16),
                      _buildFlashSaleCard(productSnap.data ?? []),
                      const SizedBox(height: 16),
                      _buildBoostButton(productSnap.data ?? []),
                      if (user?.email == 'admin@soko-langu.com') ...[
                        const SizedBox(height: 16),
                        _buildAdminSection(),
                      ],
                      if (transactions.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Transaction History',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...transactions
                            .take(10)
                            .map((tx) => _buildTransactionTile(tx)),
                      ],
                    ],
                  ),
                );
              },
            );
          },
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
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
          backgroundColor: tx.status == TransactionStatus.completed
              ? Colors.green.withAlpha(30)
              : Colors.orange.withAlpha(30),
          child: Icon(
            tx.status == TransactionStatus.completed
                ? Icons.check_circle
                : Icons.pending,
            color: tx.status == TransactionStatus.completed
                ? Colors.green
                : Colors.orange,
          ),
        ),
        title: Text(
          tx.productName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${tx.buyerName} - \$${tx.sellerReceives.toStringAsFixed(2)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${tx.totalAmount.toStringAsFixed(2)}',
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
              'Admin - Platform Earnings',
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
                  '2% Commission',
                  Colors.blueGrey,
                ),
                const SizedBox(width: 12),
                _statCard(
                  context,
                  Icons.trending_up,
                  '\$${(stats['todayEarnings'] ?? 0).toStringAsFixed(2)}',
                  'Today',
                  Colors.green,
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
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final balance = (snap.data?.data() as Map<String, dynamic>?)?['sellerBalance'] as num? ?? 0;
        final totalSales = (snap.data?.data() as Map<String, dynamic>?)?['totalSales'] as num? ?? 0;
        final nf = NumberFormat('#,###', 'en');
        return GestureDetector(
          onTap: () => context.push(AppRoutes.sellerEarnings),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF065535), Color(0xFF0B8043)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Seller Earnings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'TZS ${nf.format(balance)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalSales sales | Tap for details & withdrawal',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKycCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
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
            title = 'KYC Imekubaliwa';
            subtitle = 'Unaweza kuuza bidhaa';
            color = Colors.green;
            icon = Icons.verified;
            break;
          case 'pending':
            title = 'KYC Inakaguliwa';
            subtitle = 'Taarifa zako zinakaguliwa...';
            color = Colors.orange;
            icon = Icons.hourglass_top;
            break;
          case 'rejected':
            title = 'KYC Imekataliwa';
            subtitle = 'Bonyeza kuwasilisha tena';
            color = Colors.red;
            icon = Icons.cancel;
            break;
          default:
            title = 'KYC Haitumwa';
            subtitle = 'Thibitisha utambulisho wako kuuza';
            color = Colors.blueGrey;
            icon = Icons.verified_outlined;
        }

        return GestureDetector(
          onTap: () => context.push(AppRoutes.kyc),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withAlpha(30), color.withAlpha(10)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
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

  Widget _buildCustomizeShopButton() {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.shopCustomization),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.store, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customize Shop',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add banner & customize your shop',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
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

  Widget _buildFlashSaleCard(List<Product> products) {
    return StreamBuilder<List<FlashSale>>(
      stream: FlashSaleService().getMyFlashSales(),
      builder: (context, snap) {
        final activeCount = snap.data?.length ?? 0;
        return GestureDetector(
          onTap: () {
            if (products.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Weka bidhaa kwanza')),
              );
              return;
            }
            context.push(AppRoutes.createFlashSale);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D6A4F), Color(0xFF1B4332)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_fire_department, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Flash Sale',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeCount > 0
                            ? '$activeCount Flash Sale inayoenda'
                            : 'Unda flash sale kupunguza bei bidhaa zako',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoostButton(List<Product> products) {
    return GestureDetector(
      onTap: products.isEmpty ? null : () => _showBoostDialog(products),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6F00), Color(0xFFFFA726)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('boost_listing'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    products.isEmpty
                        ? 'Add a product first'
                        : 'Bronze TZS 1,500/3d · Silver TZS 3,000/7d · Gold TZS 10,000/30d',
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
              const Text(
                'Boost a Product',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose a product to boost',
                style: TextStyle(color: Colors.grey, fontSize: 13),
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
                          color: Colors.grey[200],
                          child: p.images.isNotEmpty
                              ? CachedNetworkImage(imageUrl: p.images.first, fit: BoxFit.cover)
                              : const Icon(Icons.image, color: Colors.grey),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        alreadyBoosted ? 'Already boosted' : 'Tap to boost',
                      ),
                      trailing: alreadyBoosted
                          ? const Icon(Icons.check_circle, color: Colors.green)
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
