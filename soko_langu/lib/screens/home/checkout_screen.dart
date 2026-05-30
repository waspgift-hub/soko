import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../models/product_model.dart';
import '../../models/cart_model.dart';
import '../../services/payment_service.dart';
import '../../services/fraud_prevention_service.dart';
import '../../services/mongike_service.dart';
import '../../services/cart_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class CheckoutScreen extends StatefulWidget {
  final dynamic product;

  const CheckoutScreen({super.key, required this.product});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _phoneController = TextEditingController();
  final _paymentService = PaymentService();
  final _cartService = CartService();
  bool _processing = false;

  List<CartItem> get _items {
    if (widget.product is List) {
      return widget.product as List<CartItem>;
    }
    final p = widget.product as Product;
    return [
      CartItem(
        productId: p.id,
        name: p.name,
        image: p.images.isNotEmpty ? p.images.first : '',
        price: p.price,
        sellerId: p.sellerId,
        sellerName: p.sellerName,
        quantity: 1,
      ),
    ];
  }

  double get _totalPrice => _items.fold<double>(0, (total, item) => total + item.price * item.quantity);

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    final breakdown = _paymentService.calculateFees(_totalPrice);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('checkout')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 56, height: 56,
                          color: cs.surfaceContainerHighest,
                          child: item.image.isNotEmpty
                              ? Image.network(item.image, fit: BoxFit.cover)
                              : const Icon(Icons.image, size: 28, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('x${item.quantity}  ${context.formatPrice(item.price * item.quantity)}', style: TextStyle(color: cs.onSurface.withAlpha(150), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Payment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 12),
          _detailRow('Total Price', context.formatPrice(_totalPrice), cs),
          _detailRow('Mongike Fee', '- ${context.formatPrice(breakdown.processingFee)}', cs, valueColor: Colors.red.shade400),
          _detailRow('Soko Langu Commission (4%)', '- ${context.formatPrice(breakdown.platformFee)}', cs, valueColor: Colors.red.shade400),
          const Divider(height: 24),
          _detailRow('Seller Receives', context.formatPrice(breakdown.sellerReceives), cs, valueColor: Colors.green.shade600),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You pay ${context.formatPrice(_totalPrice)} via Mongike. Seller receives ${context.formatPrice(breakdown.sellerReceives)} after fees.',
                    style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Your Phone Number', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSurface)),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'e.g. 0712345678',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.phone_android),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _processPayment,
              icon: _processing
                  ? const GoogleLoading(size: 20, strokeWidth: 2)
                  : const Icon(Icons.lock),
              label: Text(
                _processing ? 'Processing...' : 'Pay ${context.formatPrice(_totalPrice)}',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF065535),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _processing ? null : () => context.pop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, ColorScheme cs, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: cs.onSurface.withAlpha(170), fontSize: 14)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: valueColor)),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('Please enter your phone number');
      return;
    }

    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Please log in first');
      setState(() => _processing = false);
      return;
    }

    final items = _items;
    if (items.isEmpty) {
      _showError('Cart is empty');
      setState(() => _processing = false);
      return;
    }

    try {
      final firstItem = items.first;
      await FraudPreventionService().checkSuspiciousTransaction(
        buyerId: user.uid,
        sellerId: firstItem.sellerId,
        sellerName: firstItem.sellerName,
        amount: _totalPrice,
      );
      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: _totalPrice,
        productName: '${firstItem.name}${items.length > 1 ? ' +${items.length - 1} more' : ''}',
        productId: firstItem.productId,
        sellerId: firstItem.sellerId,
        sellerName: firstItem.sellerName,
        email: user.email ?? '',
        phone: phone,
        buyerId: user.uid,
      );

      if (result == null || result['order_id'] == null) {
        _showError('Failed to initiate payment. Try again.');
        setState(() => _processing = false);
        return;
      }

      final orderId = result['order_id'] as String;

      if (!mounted) return;
      _showPaymentDialog(orderId, user);
    } catch (e) {
      _showError('Payment error: $e');
      setState(() => _processing = false);
    }
  }

  void _showPaymentDialog(String orderId, User user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .doc(orderId)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() as Map<String, dynamic>?;
            final status = data?['status'] as String? ?? 'pending';

            if (status == 'completed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _onPaymentSuccess(orderId, user, ctx);
              });
              return const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 64),
                    SizedBox(height: 16),
                    Text('Payment Successful!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }

            if (status == 'failed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.pop(ctx);
                setState(() => _processing = false);
                _showError('Payment failed. Please try again.');
              });
              return const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cancel, color: Colors.red, size: 64),
                    SizedBox(height: 16),
                    Text('Payment Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }

            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GoogleLoading(size: 24, strokeWidth: 2),
                  const SizedBox(height: 20),
                  Text(
                    context.tr('processing_payment'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('complete_payment_mongike').replaceAll('{0}', orderId),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _onPaymentSuccess(String orderId, User user, BuildContext dialogContext) async {
    Navigator.pop(dialogContext);

    final items = _items;
    final firstItem = items.first;

    await _paymentService.processTransaction(
      buyerId: user.uid,
      buyerName: user.displayName ?? 'Buyer',
      buyerPhone: _phoneController.text.trim(),
      sellerId: firstItem.sellerId,
      sellerName: firstItem.sellerName,
      productId: firstItem.productId,
      productName: '${firstItem.name}${items.length > 1 ? ' +${items.length - 1} more' : ''}',
      productPrice: _totalPrice,
      transactionReference: orderId,
    );

    await _cartService.clearCart();

    if (mounted) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('purchase_successful')),
          backgroundColor: Colors.green.shade600,
        ),
      );
      context.go(AppRoutes.home);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}
