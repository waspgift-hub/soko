import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../services/sms_notification_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/glass_container.dart';
import '../../utils/network_error.dart';
import 'package:flutter/foundation.dart';

class SellerDispatchScreen extends StatefulWidget {
  const SellerDispatchScreen({super.key});

  @override
  State<SellerDispatchScreen> createState() => _SellerDispatchScreenState();
}

class _SellerDispatchScreenState extends State<SellerDispatchScreen> {
  String? _dispatchingTxId;
  final _formKey = GlobalKey<FormState>();

  final _courierNameCtrl = TextEditingController();
  final _trackingNumberCtrl = TextEditingController();
  final _driverPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _courierNameCtrl.dispose();
    _trackingNumberCtrl.dispose();
    _driverPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _dispatchOrder(String txId, {String buyerPhone = ''}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _dispatchingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispatch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          'courierName': _courierNameCtrl.text.trim(),
          'trackingNumber': _trackingNumberCtrl.text.trim(),
          'driverPhone': _driverPhoneCtrl.text.trim(),
          'notes': _notesCtrl.text.trim(),
        }),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        for (final c in [_courierNameCtrl, _trackingNumberCtrl, _driverPhoneCtrl, _notesCtrl]) {
          c.clear();
        }
        if (buyerPhone.isNotEmpty) {
          SmsNotificationService.notifyDispatched(
            buyerPhone: buyerPhone,
            orderId: txId,
            busName: _courierNameCtrl.text.trim(),
            plateNumber: '',
          );
        }
        if (mounted) _showSuccess(context.tr('product_dispatched_msg'));
      } else {
        if (mounted) _showError(result['error'] ?? context.tr('dispatch_failed'));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SellerDispatch error: $e');
      if (mounted) _showError(translateError(e));
    }

    setState(() => _dispatchingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('dispatch_title'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('dispatch_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('sellerId', isEqualTo: user.uid)
            .where('status', whereIn: ['paid_escrow_held', 'dispatched'])
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${context.tr('error')}: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading());
          }

          final docs = snap.data!.docs
              .where((d) => (d.data() as Map)['status'] == 'paid_escrow_held')
              .toList();
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 72, color: cs.primary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(context.tr('no_products_to_dispatch'),
                      style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(context.tr('paid_products_only_hint'),
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final txId = docs[i].id;
              final productName = d['productName'] ?? context.tr('product');
              final totalAmount = d['totalAmount'] ?? d['productPrice'] ?? 0;
              final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
              final buyerPhone = d['buyerPhone'] ?? '';
              final buyerName = d['buyerName'] ?? '';
              final addr = d['deliveryAddress'] as Map<String, dynamic>?;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlassContainer(
                  blur: 24,
                  opacity: isDark ? 0.1 : 0.06,
                  borderRadius: 22,
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock, size: 14, color: cs.primary),
                                  const SizedBox(width: 6),
                                  Text(context.tr('paid_label'), style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Text(context.formatPrice((totalAmount as num).toDouble()),
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: cs.primary)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(productName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
                        const SizedBox(height: 6),
                        if (buyerName.isNotEmpty)
                          _detailRow(cs, context.tr('buyer_label'), buyerName),
                        if (buyerPhone.isNotEmpty)
                          _detailRow(cs, context.tr('phone'), buyerPhone.toString()),
                        if (addr != null)
                          _detailRow(cs, context.tr('address'), '${addr['region'] ?? ''}, ${addr['district'] ?? ''}, ${addr['street'] ?? ''}'),
                        if (shippingCost > 0)
                          _detailRow(cs, context.tr('shipping_cost'), context.formatPrice(shippingCost)),

                        const SizedBox(height: 16),
                        Container(height: 1, color: cs.primary.withValues(alpha: 0.1)),
                        const SizedBox(height: 16),

                        Text(context.tr('shipping_details'),
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                        const SizedBox(height: 12),

                        _buildField(cs, _courierNameCtrl, context.tr('courier_company_name'), Icons.business, required: true),
                        const SizedBox(height: 10),
                        _buildField(cs, _trackingNumberCtrl, context.tr('tracking_number'), Icons.qr_code, required: true),
                        const SizedBox(height: 10),
                        _buildField(cs, _driverPhoneCtrl, context.tr('driver_phone'), Icons.phone, keyboardType: TextInputType.phone),
                        const SizedBox(height: 10),
                        _buildField(cs, _notesCtrl, context.tr('additional_notes'), Icons.notes),

                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _dispatchingTxId == txId ? null : () => _dispatchOrder(txId, buyerPhone: buyerPhone),
                            icon: _dispatchingTxId == txId
                                ? const SizedBox(width: 20, height: 20, child: GoogleLoading(size: 16, strokeWidth: 2))
                                : const Icon(Icons.local_shipping, size: 20),
                            label: Text(_dispatchingTxId == txId ? context.tr('dispatching') : context.tr('confirm_dispatch'),
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.surface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _detailRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildField(ColorScheme cs, TextEditingController ctrl, String label, IconData icon,
      {bool required = false, TextInputType? keyboardType}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      style: TextStyle(color: cs.onSurface),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(icon, size: 20, color: cs.primary),
        filled: true,
        fillColor: cs.surface.withValues(alpha: 0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? context.tr('required') : null : null,
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary),
    );
  }
}
