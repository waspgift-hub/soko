import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/order_service.dart';
import '../../services/mongike_service.dart';
import '../../models/order_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentSummaryScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final String productId;
  final String productName;
  final double productPrice;

  const PaymentSummaryScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.productId,
    required this.productName,
    required this.productPrice,
  });

  @override
  State<PaymentSummaryScreen> createState() => _PaymentSummaryScreenState();
}

class _PaymentSummaryScreenState extends State<PaymentSummaryScreen> {
  final _orderService = OrderService();
  final _userService = UserService();
  final _db = FirebaseFirestore.instance;
  bool _processing = false;
  UserProfile? _sellerProfile;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
  }

  Future<void> _loadSellerProfile() async {
    final profile = await _userService.getProfile(widget.sellerId);
    if (mounted) setState(() => _sellerProfile = profile);
  }

  Future<void> _confirmPayment() async {
    setState(() => _processing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final orderItem = OrderItem(
        productId: widget.productId,
        name: widget.productName,
        price: widget.productPrice,
        quantity: 1,
        image: null,
      );

      await _orderService.createOrder(
        items: [orderItem],
        totalAmount: widget.productPrice,
        sellerId: widget.sellerId,
        paymentMethod: 'Mobile Money',
        paymentMethodName: 'Direct Transfer',
        paymentNumber: _sellerProfile?.phone ?? '',
      );

      if (!mounted) return;
      await _db.collection('products').doc(widget.productId).update({
        'soldCount': FieldValue.increment(1),
      });
      if (!mounted) return;

      context.replace(AppRoutes.orders);
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('payment_failed')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _payWithMongike() async {
    setState(() => _processing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: widget.productPrice,
        productName: widget.productName,
        productId: widget.productId,
        sellerId: widget.sellerId,
        sellerName: widget.sellerName,
        email: user.email ?? '',
        phone: user.phoneNumber ?? '',
      );

      if (!mounted) return;
      Navigator.pop(context);

      final success = result['success'] as bool?;
      if (success == true) {
        final paymentUrl = result['paymentUrl'] as String?;
        final orderId = result['orderId'] as String?;

        final orderItem = OrderItem(
          productId: widget.productId,
          name: widget.productName,
          price: widget.productPrice,
          quantity: 1,
          image: null,
        );

        await _orderService.createOrder(
          items: [orderItem],
          totalAmount: widget.productPrice,
          sellerId: widget.sellerId,
          paymentMethod: 'Mongike',
          paymentMethodName: 'Mongike Secure Payment',
          paymentNumber: _sellerProfile?.phone ?? '',
        );

        if (!mounted) return;
        await _db.collection('products').doc(widget.productId).update({
          'soldCount': FieldValue.increment(1),
        });

        if (mounted) {
          _showMongikePaymentDialog(paymentUrl, orderId, widget.productPrice);
        }
      } else {
        if (mounted) {
          final error = result['error'] as String? ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mongike payment failed: $error')),
          );
          setState(() => _processing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mongike error: $e')),
        );
        setState(() => _processing = false);
      }
    }
  }

  void _showMongikePaymentDialog(String? paymentUrl, String? orderId, double total) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Lipa na Mongike'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet, size: 48, color: Color(0xFF6C63FF)),
            const SizedBox(height: 16),
            Text('TSh ${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Bonyeza link hapa chini kulipa kupitia Mongike:'),
            const SizedBox(height: 12),
            if (paymentUrl != null)
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(paymentUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF6C63FF)),
                  ),
                  child: const Text('🔗 Fungua Mongike Payment', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
                ),
              ),
            const SizedBox(height: 12),
            const Text('Baada ya kulipa, order yako itathibitishwa automatically.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.replace(AppRoutes.orders);
            },
            child: const Text('Nenda kwenye Orders'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.tr('copied')}: $text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('payment_summary')),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 20,
            top: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Summary
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.shopping_bag, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'TZS ${widget.productPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Payment Instructions
              Text(
                context.tr('how_to_pay'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),

              // Step-by-step guide
              _buildStepCard(
                step: 1,
                title: context.tr('step1_title'),
                desc: context.tr('step1_desc'),
                icon: Icons.phone_android,
                color: Colors.blue,
              ),
              const SizedBox(height: 8),
              _buildStepCard(
                step: 2,
                title: context.tr('step2_title'),
                desc: context.tr('step2_desc'),
                icon: Icons.send,
                color: Colors.green,
              ),
              const SizedBox(height: 8),
              _buildStepCard(
                step: 3,
                title: context.tr('step3_title'),
                desc: context.tr('step3_desc'),
                icon: Icons.check_circle,
                color: Colors.purple,
              ),
              const SizedBox(height: 20),

              // Seller Payment Info
              Card(
                color: isDark ? const Color(0xFF1A2E1A) : Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.store, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Text(
                            '${context.tr('pay_to')}: ${widget.sellerName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_sellerProfile != null) ...[
                        if (_sellerProfile!.phone.isNotEmpty)
                          _buildPaymentMethod(
                            icon: Icons.phone,
                            label: 'M-Pesa / Airtel Money',
                            value: _sellerProfile!.phone,
                            onTap: () => _copyToClipboard(_sellerProfile!.phone),
                          ),
                        if (_sellerProfile!.paymentNumbers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ..._sellerProfile!.paymentNumbers.entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildPaymentMethod(
                                icon: Icons.payment,
                                label: e.key,
                                value: e.value,
                                onTap: () => _copyToClipboard(e.value),
                              ),
                            ),
                          ),
                        ],
                      ] else
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Warning
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2E1A) : Colors.amber[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.amber[800]! : Colors.amber[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[800]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr('payment_warning'),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.amber[200] : Colors.amber[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Mongike Payment Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : _payWithMongike,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.account_balance_wallet),
                  label: Text(
                    _processing
                        ? context.tr('processing')
                        : 'Lipa na Mongike',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Confirm Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : _confirmPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(
                    _processing
                        ? context.tr('processing')
                        : context.tr('confirm_paid'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(context.tr('cancel')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required int step,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.1) : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: color, size: 20),
        ],
      ),
    );
  }

  Widget _buildPaymentMethod({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.green[600]),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy, size: 16, color: Colors.green[600]),
          ],
        ),
      ),
    );
  }
}

