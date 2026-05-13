import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:http/http.dart' as http;
import '../../services/order_service.dart';
import '../../services/product_service.dart';
import '../../services/payment_service.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../models/order_model.dart';
import '../../models/product_model.dart';
import '../../models/transaction_model.dart';
import '../live/go_live_screen.dart';
import '../seller/earnings_dashboard.dart';
import 'streamer_earnings_screen.dart';
import 'shop_customization_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  final OrderService _orderService = OrderService();
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
            final transactions = txSnap.data ?? [];

            return StreamBuilder<List<Order>>(
              stream: _orderService.getReceivedOrders(),
              builder: (context, orderSnap) {
                final orders = orderSnap.data ?? [];

                return StreamBuilder<List<Product>>(
                  stream: _productService.getMyProducts(),
                  builder: (context, productSnap) {
                    final productCount = productSnap.data?.length ?? 0;
                    final pendingOrders = orders
                        .where((o) => o.status == OrderStatus.pending)
                        .length;
                    final completedTx = transactions.where(
                      (t) => t.status == TransactionStatus.completed,
                    );
                    final txRevenue = completedTx.fold<double>(
                      0,
                      (total, t) => total + t.sellerReceives,
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
                                'Total Sales',
                                Colors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _statCard(
                                context,
                                Icons.monetization_on,
                                '\$${txRevenue.toStringAsFixed(2)}',
                                'Amount Received',
                                Colors.green,
                              ),
                              const SizedBox(width: 12),
                              _statCard(
                                context,
                                Icons.hourglass_empty,
                                pendingOrders.toString(),
                                context.tr('pending'),
                                Colors.red,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildEarningsCard(),
                          const SizedBox(height: 16),
                          _buildCustomizeShopButton(),
                          const SizedBox(height: 16),
                          _buildBoostButton(productSnap.data ?? []),
                          const SizedBox(height: 16),
                          _buildGoLiveButton(productSnap.data ?? []),
                          const SizedBox(height: 16),
                          _buildStreamerEarningsCard(),
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
                          if (orders.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              context.tr('recent_orders'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            ...orders
                                .take(5)
                                .map((order) => _buildOrderTile(order)),
                          ],
                        ],
                      ),
                    );
                  },
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
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(MarketplaceTransaction tx) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                color: Colors.green[700],
              ),
            ),
            Text(
              '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTile(Order order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.buyerName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                _statusChip(order.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '\$${order.totalAmount.toStringAsFixed(0)} - ${order.items.length} items',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EarningsDashboard()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.monetization_on, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ad Revenue Earnings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Tap to view your earnings dashboard',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamerEarningsCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (ctx, snap) {
        final earnings =
            (snap.data?.data() as Map<String, dynamic>?)?['streamerEarnings'] ??
            0;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StreamerEarningsScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.card_giftcard, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('streamer_earnings'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'TZS $earnings from gifts — Tap to view',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomizeShopButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShopCustomizationScreen()),
      ),
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
                    'Add banner & colors — Premium only',
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
                        : 'Feature your product for TZS 5,000 / 30 days',
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
                'TZS 5,000 — Featured for 30 days',
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
                    final alreadyFeatured = p.isFeaturedValid;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 48,
                          height: 48,
                          color: Colors.grey[200],
                          child: p.images.isNotEmpty
                              ? Image.network(p.images.first, fit: BoxFit.cover)
                              : const Icon(Icons.image, color: Colors.grey),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        alreadyFeatured ? 'Already featured' : 'Tap to boost',
                      ),
                      trailing: alreadyFeatured
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: alreadyFeatured
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _processBoostPayment(p);
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

  Future<void> _processBoostPayment(Product product) async {
    final phoneController = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Boost Listing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Boost "${product.name}" for TZS 5,000 for 30 days?'),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: InputDecoration(
                labelText: context.tr('mpesa_phone'),
                hintText: 'e.g. 0712345678',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, phoneController.text.trim()),
            child: Text(context.tr('pay_boost')),
          ),
        ],
      ),
    );

    if (phone == null || phone.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/boost-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'productId': product.id,
          'phone': phone,
          'userId': user.uid,
        }),
      );

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['message'] != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data['message'])));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data['error'] ?? 'Failed')));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("${context.tr('error')}: $e")));
    }
  }

  Widget _buildGoLiveButton(List<Product> products) {
    return GestureDetector(
      onTap: products.isEmpty ? null : () => _showGoLiveDialog(products),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFFF6F00)],
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
              child: const Icon(
                Icons.wifi_tethering,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Go Live',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    products.isEmpty
                        ? 'Add a product first to go live'
                        : 'Start a live stream for your products',
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

  void _showGoLiveDialog(List<Product> products) {
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
                'Select Product to Go Live',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final p = products[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 48,
                          height: 48,
                          color: Colors.grey[200],
                          child: p.images.isNotEmpty
                              ? Image.network(p.images.first, fit: BoxFit.cover)
                              : const Icon(Icons.image, color: Colors.grey),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('TZS ${p.price.toStringAsFixed(0)}'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GoLiveScreen(
                              productId: p.id,
                              productName: p.name,
                              productImage: p.images.isNotEmpty
                                  ? p.images.first
                                  : null,
                            ),
                          ),
                        );
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

  Widget _statusChip(OrderStatus status) {
    Color color;
    switch (status) {
      case OrderStatus.pending:
        color = Colors.orange;
        break;
      case OrderStatus.confirmed:
        color = Colors.blue;
        break;
      case OrderStatus.processing:
        color = Colors.blueGrey;
        break;
      case OrderStatus.shipped:
        color = Colors.indigo;
        break;
      case OrderStatus.delivered:
        color = Colors.green;
        break;
      case OrderStatus.cancelled:
        color = Colors.red;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        context.tr(status.toString().split('.').last),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
