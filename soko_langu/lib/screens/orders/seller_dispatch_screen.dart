import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/location_map_widget.dart';
import '../../widgets/ds/ds.dart';

/// Seller flow after escrow: hela ikiwekwa escrow, seller anaweka gharama ya
/// usafirishaji, kisha anaweka taarifa za kutuma mzigo (courier). Hatua zote
/// mbili ziko kwenye screen hii kwa kila order.
class SellerDispatchScreen extends StatefulWidget {
  const SellerDispatchScreen({super.key});

  @override
  State<SellerDispatchScreen> createState() => _SellerDispatchScreenState();
}

class _SellerDispatchScreenState extends State<SellerDispatchScreen> {
  String? _dispatchingTxId;
  String? _settingCostTxId;
  final Map<String, TextEditingController> _shippingCostCtrls = {};
  final Map<String, TextEditingController> _courierNameCtrls = {};
  final Map<String, TextEditingController> _trackingCtrls = {};
  final Map<String, TextEditingController> _driverPhoneCtrls = {};
  final Map<String, TextEditingController> _notesCtrls = {};

  @override
  void dispose() {
    for (final c in _shippingCostCtrls.values) c.dispose();
    for (final c in _courierNameCtrls.values) c.dispose();
    for (final c in _trackingCtrls.values) c.dispose();
    for (final c in _driverPhoneCtrls.values) c.dispose();
    for (final c in _notesCtrls.values) c.dispose();
    super.dispose();
  }

  TextEditingController _shipCtrl(String txId) => _shippingCostCtrls.putIfAbsent(txId, () => TextEditingController());
  TextEditingController _courierCtrl(String txId) => _courierNameCtrls.putIfAbsent(txId, () => TextEditingController());
  TextEditingController _trackCtrl(String txId) => _trackingCtrls.putIfAbsent(txId, () => TextEditingController());
  TextEditingController _phoneCtrl(String txId) => _driverPhoneCtrls.putIfAbsent(txId, () => TextEditingController());
  TextEditingController _notesCtrl(String txId) => _notesCtrls.putIfAbsent(txId, () => TextEditingController());

  Future<void> _setShippingCost(String txId, double productPrice) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final cost = double.tryParse(_shipCtrl(txId).text.trim().replaceAll(',', ''));
    if (cost == null || cost <= 0) {
      _showError(context.tr('enter_valid_shipping_cost'));
      return;
    }
    setState(() => _settingCostTxId = txId);
    HapticFeedback.lightImpact();
    try {
      // Try server endpoint first (updates totalAmount + notifies buyer)
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/set-shipping-cost'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'orderId': txId, 'shippingCost': cost}),
      );
      if (resp.statusCode == 200) {
        _shipCtrl(txId).clear();
        if (mounted) _showSuccess(context.tr('shipping_cost_submitted'));
        return;
      }
      // Fallback: direct Firestore write (rule allows shippingCost)
      if (resp.statusCode == 404) {
        final doc = FirebaseFirestore.instance.collection('transactions').doc(txId);
        final total = productPrice + cost;
        await doc.update({'shippingCost': cost, 'totalAmount': total});
        // also sync orders mirror if exists
        try {
          await FirebaseFirestore.instance.collection('orders').doc(txId).update({'shippingCost': cost, 'totalAmount': total});
        } catch (_) {}
        _shipCtrl(txId).clear();
        if (mounted) _showSuccess(context.tr('shipping_cost_submitted'));
        return;
      }
      final body = jsonDecode(resp.body);
      _showError(body['error'] ?? context.tr('dispatch_failed'));
    } catch (e) {
      // Last fallback direct write
      try {
        final doc = FirebaseFirestore.instance.collection('transactions').doc(txId);
        final total = productPrice + cost;
        await doc.update({'shippingCost': cost, 'totalAmount': total});
        _shipCtrl(txId).clear();
        if (mounted) _showSuccess(context.tr('shipping_cost_submitted'));
      } catch (_) {
        if (mounted) _showError(context.trError(e));
      }
    } finally {
      if (mounted) setState(() => _settingCostTxId = null);
    }
  }

  Future<void> _dispatchOrder(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final courier = _courierCtrl(txId).text.trim();
    final tracking = _trackCtrl(txId).text.trim();
    if (courier.isEmpty || tracking.isEmpty) {
      _showError(context.tr('required'));
      return;
    }
    setState(() => _dispatchingTxId = txId);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispatch'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${await user.getIdToken()}'},
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          'courierName': courier,
          'trackingNumber': tracking,
          'driverPhone': _phoneCtrl(txId).text.trim(),
          'notes': _notesCtrl(txId).text.trim(),
        }),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        for (final c in [_courierCtrl(txId), _trackCtrl(txId), _phoneCtrl(txId), _notesCtrl(txId)]) c.clear();
        if (mounted) _showSuccess(context.tr('product_dispatched_msg'));
      } else {
        if (mounted) _showError(result['error'] ?? context.tr('dispatch_failed'));
      }
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    }
    if (mounted) setState(() => _dispatchingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(appBar: AppBar(title: Text(context.tr('dispatch_title'))), body: Center(child: Text(context.tr('login_required'))));
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('dispatch_title')), backgroundColor: Colors.transparent, elevation: 0),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('transactions').where('sellerId', isEqualTo: user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${context.tr('error')}: ${snap.error}'));
          if (!snap.hasData) return const Center(child: GoogleLoading());
          final docs = snap.data!.docs
              .where((d) => (d.data() as Map)['status'] == 'escrow_hold' || (d.data() as Map)['status'] == 'paid_escrow_held')
              .where((d) => (d.data() as Map)['deletedForSeller'] != true)
              .toList();
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });
          if (docs.isEmpty) {
            return DsEmptyState(icon: Icons.check_circle_outline, title: context.tr('no_products_to_dispatch'), body: context.tr('paid_products_only_hint'), tint: cs.successGreen);
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final txId = docs[i].id;
                return _buildDispatchCard(context, cs, d, txId);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildDispatchCard(BuildContext context, ColorScheme cs, Map<String, dynamic> d, String txId) {
    final productName = d['productName'] ?? context.tr('product');
    final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
    final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? productPrice + shippingCost;
    final buyerPhone = d['buyerPhone'] ?? '';
    final buyerName = d['buyerName'] ?? '';
    final addr = d['deliveryAddress'] as Map<String, dynamic>? ?? (d['region'] != null ? {'region': d['region'], 'district': d['district'], 'ward': d['ward'], 'street': d['street'], 'latitude': d['latitude'], 'longitude': d['longitude']} : null);
    final hasShipping = shippingCost > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DsCard(
        radius: 20,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cs.primary, cs.primary.withValues(alpha: 0.35)]))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        DsBadge(label: context.tr('paid_label'), color: cs.successGreen, icon: Icons.lock_outline),
                        const Spacer(),
                        Text(context.formatPrice(totalAmount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: cs.primary)),
                      ]),
                      const SizedBox(height: 12),
                      Text(productName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      const SizedBox(height: 8),
                      if (buyerName.isNotEmpty) _infoRow(cs, Icons.person_outline, context.tr('buyer_label'), buyerName),
                      if (buyerPhone.isNotEmpty) _infoRow(cs, Icons.phone_outlined, context.tr('phone'), buyerPhone.toString()),
                      if (addr != null) _infoRow(cs, Icons.place_outlined, context.tr('address'), '${addr['region'] ?? ''}, ${addr['district'] ?? ''}${(addr['ward'] as String? ?? '').isNotEmpty ? ', ${addr['ward']}' : ''}, ${addr['street'] ?? ''}'),
                      if (addr != null && addr['latitude'] != null && addr['longitude'] != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(borderRadius: BorderRadius.circular(12), child: LocationMapWidget(targetLat: (addr['latitude'] as num).toDouble(), targetLng: (addr['longitude'] as num).toDouble(), targetLabel: buyerName, height: 120, showDistance: true, interactive: false)),
                      ],
                      const SizedBox(height: 12),
                      // ── Step 1: Seller sets shipping cost after escrow ──
                      if (!hasShipping) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.primary.withValues(alpha: 0.2))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [Icon(Icons.payments_outlined, size: 16, color: cs.primary), const SizedBox(width: 6), Text(context.tr('set_cost_note'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.primary))]),
                              const SizedBox(height: 4),
                              Text(context.tr('seller_quote_subtitle'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                              const SizedBox(height: 12),
                              DsTextField(controller: _shipCtrl(txId), label: context.tr('shipping_cost'), hint: 'TZS 0', prefixIcon: Icons.monetization_on_outlined, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))]),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: _settingCostTxId == txId ? null : () => _setShippingCost(txId, productPrice),
                                  icon: _settingCostTxId == txId ? const GoogleLoading(size: 18, strokeWidth: 2) : const Icon(Icons.check, size: 18),
                                  label: Text(_settingCostTxId == txId ? context.tr('sending_label') : context.tr('send_shipping_to_buyer')),
                                  style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        _infoRow(cs, Icons.local_shipping_outlined, context.tr('shipping_cost'), context.formatPrice(shippingCost)),
                        const SizedBox(height: 12),
                        Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
                        const SizedBox(height: 12),
                        // ── Step 2: Dispatch after cost set ──
                        DsTextField(controller: _courierCtrl(txId), label: context.tr('courier_company_name'), prefixIcon: Icons.business_outlined),
                        const SizedBox(height: 12),
                        DsTextField(controller: _trackCtrl(txId), label: context.tr('tracking_number'), prefixIcon: Icons.qr_code_2),
                        const SizedBox(height: 12),
                        DsTextField(controller: _phoneCtrl(txId), label: context.tr('driver_phone'), prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                        const SizedBox(height: 12),
                        DsTextField(controller: _notesCtrl(txId), label: context.tr('additional_notes'), prefixIcon: Icons.notes, maxLines: 2),
                        const SizedBox(height: 14),
                        DsButton(label: _dispatchingTxId == txId ? context.tr('dispatching') : context.tr('confirm_dispatch'), icon: Icons.local_shipping_outlined, loading: _dispatchingTxId == txId, onPressed: _dispatchingTxId == txId ? null : () => _dispatchOrder(txId)),
                      ],
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

  Widget _infoRow(ColorScheme cs, IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [Icon(icon, size: 14, color: cs.onSurfaceVariant), const SizedBox(width: 6), Text('$label: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)), Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500)))]));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary));
  }
}
