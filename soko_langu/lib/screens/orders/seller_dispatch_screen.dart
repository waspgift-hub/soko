import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../services/sms_notification_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import 'package:flutter/foundation.dart';

class SellerDispatchScreen extends StatefulWidget {
  const SellerDispatchScreen({super.key});

  @override
  State<SellerDispatchScreen> createState() => _SellerDispatchScreenState();
}

class _SellerDispatchScreenState extends State<SellerDispatchScreen> {
  String? _dispatchingTxId;
  final _formKey = GlobalKey<FormState>();

  // ── 11 bus receipt text controllers ──
  final _passengerNameCtrl = TextEditingController();
  final _busNameCtrl = TextEditingController();
  final _receiptNumberCtrl = TextEditingController();
  final _departureTimeCtrl = TextEditingController();
  final _arrivalTimeCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _travelDateCtrl = TextEditingController();
  final _travelDayCtrl = TextEditingController();
  final _shippingFareCtrl = TextEditingController();
  final _plateNumberCtrl = TextEditingController();

  Map<String, dynamic> _receiptData() => {
    'passengerName': _passengerNameCtrl.text.trim(),
    'busName': _busNameCtrl.text.trim(),
    'receiptNumber': _receiptNumberCtrl.text.trim(),
    'departureTime': _departureTimeCtrl.text.trim(),
    'arrivalTime': _arrivalTimeCtrl.text.trim(),
    'originStation': _originCtrl.text.trim(),
    'destinationStation': _destinationCtrl.text.trim(),
    'travelDate': _travelDateCtrl.text.trim(),
    'travelDay': _travelDayCtrl.text.trim(),
    'shippingFare': double.tryParse(_shippingFareCtrl.text.trim()) ?? 0,
    'plateNumber': _plateNumberCtrl.text.trim(),
  };

  Future<void> _dispatchOrder(String txId, {String buyerPhone = ''}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _dispatchingTxId = txId);

    try {
      final receipt = _receiptData();
      if (kDebugMode) debugPrint('SellerDispatch: sending receipt data=$receipt');

      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispatch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          ...receipt,
        }),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        final busName = _busNameCtrl.text.trim();
        final plateNumber = _plateNumberCtrl.text.trim();
        for (final c in [
          _passengerNameCtrl, _busNameCtrl, _receiptNumberCtrl,
          _departureTimeCtrl, _arrivalTimeCtrl, _originCtrl,
          _destinationCtrl, _travelDateCtrl, _travelDayCtrl,
          _shippingFareCtrl, _plateNumberCtrl,
        ]) {
          c.clear();
        }
        if (buyerPhone.isNotEmpty) {
          SmsNotificationService.notifyDispatched(
            buyerPhone: buyerPhone,
            orderId: txId,
            busName: busName,
            plateNumber: plateNumber,
          );
        }
        if (mounted) _showSuccess('Bidhaa imesafirishwa! Risiti ya digital imetumwa.');
      } else {
        if (mounted) _showError(result['error'] ?? 'Failed to dispatch');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SellerDispatch error: $e');
      if (mounted) _showError('Error: $e');
    }

    setState(() => _dispatchingTxId = null);
  }

  @override
  void dispose() {
    for (final c in [
      _passengerNameCtrl, _busNameCtrl, _receiptNumberCtrl,
      _departureTimeCtrl, _arrivalTimeCtrl, _originCtrl,
      _destinationCtrl, _travelDateCtrl, _travelDayCtrl,
      _shippingFareCtrl, _plateNumberCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tuma Bidhaa kwa Basi')),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tuma Bidhaa kwa Basi')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('sellerId', isEqualTo: user.uid)
            .where('status', whereIn: ['paid_escrow_held', 'dispatched'])
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
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
                  Icon(Icons.inventory_2_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('Hakuna bidhaa zinazosubiri kusafirishwa',
                      style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
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
              final productName = d['productName'] ?? 'Product';
              final totalAmount = d['totalAmount'] ?? d['productPrice'] ?? 0;
              final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
              final buyerPhone = d['buyerPhone'] ?? '';
              final buyerName = d['buyerName'] ?? '';
              final addr = d['deliveryAddress'] as Map<String, dynamic>?;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.payment, color: cs.primary, size: 20),
                            const SizedBox(width: 8),
                            Text('Imelipwa — Tuma sasa',
                                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                            const Spacer(),
                            Text(context.formatPrice((totalAmount as num).toDouble()),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(productName, style: const TextStyle(fontSize: 15)),
                        if (buyerName.isNotEmpty)
                          Text('Mnunuzi: $buyerName',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        if (buyerPhone.isNotEmpty)
                          Text('Simu: $buyerPhone',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        if (addr != null) ...[
                          const SizedBox(height: 4),
                          Text('Anwani: ${addr['region'] ?? ''}, ${addr['district'] ?? ''}, ${addr['street'] ?? ''}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                        if (shippingCost > 0)
                          Text('Gharama ya usafirishaji: ${context.formatPrice(shippingCost)}',
                              style: TextStyle(fontSize: 12, color: cs.secondary)),
                        const Divider(height: 20),
                        Text('Risiti ya Usafirishaji kwa Basi',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
                        const SizedBox(height: 8),
                        _buildField(_passengerNameCtrl, 'Jina la Abiria / Mteja', Icons.person, required: true),
                        _buildField(_busNameCtrl, 'Jina la Basi', Icons.directions_bus, required: true),
                        _buildField(_receiptNumberCtrl, 'Namba ya Risiti ya Basi', Icons.receipt, required: true),
                        _buildField(_departureTimeCtrl, 'Muda wa Kuondoka (mf: 8:00 AM)', Icons.schedule, required: true),
                        _buildField(_arrivalTimeCtrl, 'Muda wa Kufika (mf: 2:00 PM)', Icons.access_time, required: true),
                        _buildField(_originCtrl, 'Sehemu ya Kuondokea (mji)', Icons.trip_origin, required: true),
                        _buildField(_destinationCtrl, 'Sehemu ya Kuelekea (mji)', Icons.location_on, required: true),
                        _buildField(_travelDateCtrl, 'Tarehe ya Usafiri (mf: 15/07/2026)', Icons.calendar_today, required: true),
                        _buildField(_travelDayCtrl, 'Siku ya Usafiri (mf: Jumatatu)', Icons.wb_sunny, required: true),
                        _buildField(_shippingFareCtrl, 'Nauli iliyolipwa (TZS)', Icons.money, keyboardType: TextInputType.number, required: true),
                        _buildField(_plateNumberCtrl, 'Plate Namba ya Gari', Icons.directions_car, required: true),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: cs.secondary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Nakili data hizi kutoka kwenye risiti yako ya basi. Mnunuzi ataona Digital Receipt yenye QR Code.',
                                  style: TextStyle(color: cs.secondary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _dispatchingTxId == txId ? null : () => _dispatchOrder(txId, buyerPhone: buyerPhone),
                            icon: _dispatchingTxId == txId
                                ? const SizedBox(width: 16, height: 16, child: GoogleLoading(size: 16, strokeWidth: 2))
                                : const Icon(Icons.local_shipping, size: 18),
                            label: Text(_dispatchingTxId == txId ? 'Inasafirisha...' : 'Tuma Bidhaa'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.surface,
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

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, {bool required = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: Icon(icon, size: 20),
        ),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
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
