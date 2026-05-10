import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_service.dart';
import '../../services/order_service.dart';
import '../../models/order_model.dart';
import '../../extensions/context_tr.dart';
import '../order/my_orders_screen.dart';

class PaymentSummaryScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final String productId;
  final String productName;
  final double productPrice;
  final String paymentMethod;

  const PaymentSummaryScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.productId,
    required this.productName,
    required this.productPrice,
    required this.paymentMethod,
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
    if (mounted) {
      setState(() => _sellerProfile = profile);
    }
  }

  Future<void> _iHavePaid() async {
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
        paymentMethod: 'Direct (M-Pesa/Airtel)',
        paymentMethodName: 'Direct Transfer',
        paymentNumber: _sellerProfile?.phone ?? '',
      );

      if (!mounted) return;

      await _db.collection('products').doc(widget.productId).update({
        'soldCount': FieldValue.increment(1),
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('order_placed'))));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('payment_failed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text('Payment Summary')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.blue),
            const SizedBox(height: 8),
            Text(
              'Send Payment Directly to Seller',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'After sending payment, tap "I\'ve Paid" below',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _row(context, 'Product', widget.productName),
                    const Divider(),
                    _row(
                      context,
                      'Price',
                      'TZS ${widget.productPrice.toStringAsFixed(0)}',
                      bold: true,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: Colors.green[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Send payment to ${widget.sellerName}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_sellerProfile != null) ...[
                      if (_sellerProfile!.phone.isNotEmpty) ...[
                        _paymentInfoRow(
                          Icons.phone,
                          'Phone',
                          _sellerProfile!.phone,
                        ),
                      ],
                      if (_sellerProfile!.paymentNumbers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Payment Methods:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.green[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        ..._sellerProfile!.paymentNumbers.entries.map(
                          (e) => _paymentInfoRow(Icons.payment, e.key, e.value),
                        ),
                      ],
                    ] else ...[
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber[800], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'After sending money via M-Pesa/Airtel/Mixx, tap "I\'ve Paid" below so the seller knows to confirm.',
                      style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _iHavePaid,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
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
                      ? 'Processing...'
                      : "I've Paid - TZS ${widget.productPrice.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel'),
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
    );
  }

  Widget _paymentInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.green[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
          GestureDetector(
            onTap: () {},
            child: Icon(Icons.copy, size: 16, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
    double size = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: size - 2),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
              fontSize: size,
            ),
          ),
        ],
      ),
    );
  }
}
