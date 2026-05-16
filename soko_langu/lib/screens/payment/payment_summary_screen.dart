import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/order_service.dart';
import '../../services/mongike_service.dart';
import '../../models/order_model.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

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
  bool _mongikeProcessing = false;
  final _phoneController = TextEditingController();
  UserProfile? _sellerProfile;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
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
      context.replace(AppRoutes.orders);
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('payment_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _payViaMongike() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('enter_phone'))));
      return;
    }
    setState(() => _mongikeProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: widget.productPrice,
        productName: widget.productName,
        productId: widget.productId,
        sellerId: widget.sellerId,
        sellerName: widget.sellerName,
        email: user.email ?? '',
        phone: phone,
      );
      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text(context.tr('mongike_prompt_sent')),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr('payment_failed'))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('payment_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _mongikeProcessing = false);
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
          padding: EdgeInsets.only(
            left: 20,
            top: 20,
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
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
                        context.tr('price'),
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
                          Icon(
                            Icons.person,
                            color: Colors.green[700],
                            size: 20,
                          ),
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
                            context.tr('phone'),
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
                            (e) =>
                                _paymentInfoRow(Icons.payment, e.key, e.value),
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
                    Icon(
                      Icons.warning_amber,
                      color: Colors.amber[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr('send_money_mpesa'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Mongike Payment ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.mobile_friendly,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.tr('pay_via_mongike'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '+255 7XX XXX XXX',
                          labelText: context.tr('phone'),
                          prefixIcon: const Icon(Icons.phone),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _mongikeProcessing ? null : _payViaMongike,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                          ),
                          icon: _mongikeProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.mobile_friendly),
                          label: Text(
                            _mongikeProcessing
                                ? context.tr('processing')
                                : 'Pay TZS ${widget.productPrice.toStringAsFixed(0)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Or pay directly ──
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      context.tr('or'),
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),

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
                        ? context.tr('processing')
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
    );
  }
}
