import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/location_map_widget.dart';
import '../../widgets/ds/ds.dart';

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

  Future<void> _dispatchOrder(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _dispatchingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispatch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
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
        if (mounted) _showSuccess(context.tr('product_dispatched_msg'));
      } else {
        if (mounted) _showError(result['error'] ?? context.tr('dispatch_failed'));
      }
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    }

    setState(() => _dispatchingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${context.tr('error')}: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading());
          }

          final docs = snap.data!.docs
              .where((d) => (d.data() as Map)['status'] == 'escrow_hold' ||
                  (d.data() as Map)['status'] == 'paid_escrow_held')
              .where((d) => (d.data() as Map)['deletedForSeller'] != true)
              .toList();
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

          if (docs.isEmpty) {
            return DsEmptyState(
              icon: Icons.check_circle_outline,
              title: context.tr('no_products_to_dispatch'),
              body: context.tr('paid_products_only_hint'),
              tint: cs.successGreen,
            );
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
    final totalAmount = (d['totalAmount'] ?? d['productPrice'] ?? 0) as num;
    final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
    final buyerPhone = d['buyerPhone'] ?? '';
    final buyerName = d['buyerName'] ?? '';
    final addr = d['deliveryAddress'] as Map<String, dynamic>?
        // orders-format docs keep the address as flat fields at top level
        ?? (d['region'] != null
            ? {
                'region': d['region'],
                'district': d['district'],
                'ward': d['ward'],
                'street': d['street'],
                'latitude': d['latitude'],
                'longitude': d['longitude'],
              }
            : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        radius: 20,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [cs.primary, cs.primary.withValues(alpha: 0.35)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DsBadge(
                            label: context.tr('paid_label'),
                            color: cs.successGreen,
                            icon: Icons.lock_outline,
                          ),
                          const Spacer(),
                          Text(context.formatPrice(totalAmount.toDouble()),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: cs.primary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(productName,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      const SizedBox(height: 8),
                      if (buyerName.isNotEmpty)
                        _infoRow(cs, Icons.person_outline, context.tr('buyer_label'), buyerName),
                      if (buyerPhone.isNotEmpty)
                        _infoRow(cs, Icons.phone_outlined, context.tr('phone'), buyerPhone.toString()),
                      if (addr != null)
                        _infoRow(cs, Icons.place_outlined, context.tr('address'),
                            '${addr['region'] ?? ''}, ${addr['district'] ?? ''}${(addr['ward'] as String? ?? '').isNotEmpty ? ', ${addr['ward']}' : ''}, ${addr['street'] ?? ''}'),
                      if (addr != null && addr['latitude'] != null && addr['longitude'] != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LocationMapWidget(
                            targetLat: (addr['latitude'] as num).toDouble(),
                            targetLng: (addr['longitude'] as num).toDouble(),
                            targetLabel: buyerName,
                            height: 120,
                            showDistance: true,
                            interactive: false,
                          ),
                        ),
                      ],
                      if (shippingCost > 0)
                        _infoRow(cs, Icons.local_shipping_outlined, context.tr('shipping_cost'),
                            context.formatPrice(shippingCost)),
                      if (d['buyerTransport'] != null)
                        _buyerTransportCard(cs, d['buyerTransport'] as Map<String, dynamic>),
                      const SizedBox(height: 12),
                      Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
                      const SizedBox(height: 12),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            DsTextField(
                              controller: _courierNameCtrl,
                              label: context.tr('courier_company_name'),
                              prefixIcon: Icons.business_outlined,
                              validator: (v) => (v == null || v.trim().isEmpty) ? context.tr('required') : null,
                            ),
                            const SizedBox(height: 12),
                            DsTextField(
                              controller: _trackingNumberCtrl,
                              label: context.tr('tracking_number'),
                              prefixIcon: Icons.qr_code_2,
                              validator: (v) => (v == null || v.trim().isEmpty) ? context.tr('required') : null,
                            ),
                            const SizedBox(height: 12),
                            DsTextField(
                              controller: _driverPhoneCtrl,
                              label: context.tr('driver_phone'),
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            DsTextField(
                              controller: _notesCtrl,
                              label: context.tr('additional_notes'),
                              prefixIcon: Icons.notes,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 14),
                            DsButton(
                              label: _dispatchingTxId == txId
                                  ? context.tr('dispatching')
                                  : context.tr('confirm_dispatch'),
                              icon: Icons.local_shipping_outlined,
                              loading: _dispatchingTxId == txId,
                              onPressed: _dispatchingTxId == txId
                                  ? null
                                  : () => _dispatchOrder(txId),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buyerTransportCard(ColorScheme cs, Map<String, dynamic> t) {
    final method = t['method'] as String? ?? '';
    final methodLabel = method == 'bus'
        ? context.tr('transport_bus')
        : method == 'bodaboda'
            ? context.tr('transport_bodaboda')
            : context.tr('transport_pikipiki');
    final company = t['companyName'] as String? ?? '';
    final plate = t['plateNumber'] as String? ?? '';
    final driver = t['driverName'] as String? ?? '';
    final phone = t['driverPhone'] as String? ?? '';
    final note = t['note'] as String? ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                context.tr('buyer_transport_label'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _infoRow(cs, Icons.directions_outlined, context.tr('transport_method'), methodLabel),
          if (company.isNotEmpty)
            _infoRow(cs, Icons.business_outlined, context.tr('transport_company'), company),
          if (plate.isNotEmpty)
            _infoRow(cs, Icons.pin_outlined, context.tr('transport_plate'), plate),
          if (driver.isNotEmpty)
            _infoRow(cs, Icons.person_outline, context.tr('transport_driver_name'), driver),
          if (phone.isNotEmpty)
            _infoRow(cs, Icons.phone_outlined, context.tr('driver_phone'), phone),
          if (note.isNotEmpty)
            _infoRow(cs, Icons.notes, context.tr('transport_note'), note),
        ],
      ),
    );
  }

  Widget _infoRow(ColorScheme cs, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
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
