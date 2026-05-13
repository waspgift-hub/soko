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

  Future<void> _payDirect() async {
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
      if (!mounted) return;

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
      appBar: AppBar(
        title: Text(context.tr('payment_summary')),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(left: 20, top: 20, right: 20, bottom: MediaQuery.of(context).padding.bottom + 20),
          child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _row(context, context.tr('product'), widget.productName),
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

            // ── Direct Transfer to Seller ──
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
                          '${context.tr('send_payment_to')} ${widget.sellerName}',
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
                      if (_sellerProfile!.phone.isNotEmpty)
                        _paymentInfoRow(
                          Icons.phone,
                          'Phone',
                          _sellerProfile!.phone,
                        ),
                      if (_sellerProfile!.paymentNumbers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.tr('payment_methods_label'),
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
                    ] else
                      const Center(child: CircularProgressIndicator()),
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
                      context.tr('send_money_mpesa'),
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
                onPressed: _processing ? null : _payDirect,
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
                      ? 'Processing...'
                      : '${context.tr('paid_button')} TZS ${widget.productPrice.toStringAsFixed(0)}',
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
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
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
              fontSize: size,
              ),
            ),
          ],
        ),
      ),
      );
  }
}
