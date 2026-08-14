import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../utils/network_error.dart';
import '../../widgets/ds/ds.dart';

class SellerQuoteScreen extends StatefulWidget {
  const SellerQuoteScreen({super.key});

  @override
  State<SellerQuoteScreen> createState() => _SellerQuoteScreenState();
}

class _SellerQuoteScreenState extends State<SellerQuoteScreen> {
  final _shippingCostCtrl = TextEditingController();
  String? _quotingTxId;

  @override
  void dispose() {
    _shippingCostCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitQuote(String txId, String buyerId, String productName) async {
    final costText = _shippingCostCtrl.text.trim();
    final cost = double.tryParse(costText);
    if (cost == null || cost <= 0) {
      _showError(context.tr('enter_valid_shipping_cost'));
      return;
    }

    setState(() => _quotingTxId = txId);
    HapticFeedback.lightImpact();

    try {
      // The server owns the quoted transition: it updates orders/{id} and the
      // transactions/{id} mirror (shippingCost + totalAmount) atomically via
      // transitionOrder, so a failed server call can't leave the docs divergent.
      var transitionOk = false;
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final resp = await http.post(
            Uri.parse('${ApiConfig.baseUrl}/api/orders/transition'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'orderId': txId,
              'newStatus': 'quoted',
              'note': jsonEncode({'shippingCost': cost}),
            }),
          );
          transitionOk = resp.statusCode == 200;
        }
      } catch (_) {}

      // If the server sync failed the buyer never got notified — make the
      // seller aware so they can retry.
      if (!transitionOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('quote_sync_warning')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }

      _shippingCostCtrl.clear();
      if (mounted) _showSuccess(context.tr('shipping_cost_submitted'));
    } catch (e) {
      if (mounted) _showError(translateError(e));
    }

    setState(() => _quotingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('shipping_quote'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('shipping_quote')),
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
              .where((d) => (d.data() as Map)['status'] == 'awaiting_shipping_quote')
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
              icon: Icons.inbox_outlined,
              title: context.tr('no_shipping_requests'),
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
                return _buildQuoteCard(context, cs, d, txId);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuoteCard(BuildContext context, ColorScheme cs, Map<String, dynamic> d, String txId) {
    final productName = d['productName'] ?? context.tr('product');
    final productImage = d['productImage'] as String? ?? '';
    final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
    final buyerName = d['buyerName'] ?? '';
    final buyerPhone = d['buyerPhone'] as String? ?? '';
    final buyerId = d['buyerId'] ?? '';
    final addrNested = d['deliveryAddress'] as Map<String, dynamic>?;
    // The orders API stores the address as flat fields
    // (region/district/ward/street/landmarks); fall back to them when the
    // nested deliveryAddress map is absent.
    final addr = addrNested ??
        <String, dynamic>{
          'region': d['region'] ?? '',
          'district': d['district'] ?? '',
          'ward': d['ward'] ?? '',
          'street': d['street'] ?? '',
          'landmarks': d['landmarks'] ?? '',
        };
    final hasAddr = (addr['region'] as String? ?? '').isNotEmpty ||
        (addr['district'] as String? ?? '').isNotEmpty ||
        (addr['ward'] as String? ?? '').isNotEmpty ||
        (addr['street'] as String? ?? '').isNotEmpty ||
        (addr['landmarks'] as String? ?? '').isNotEmpty;

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
                    colors: [cs.tertiary, cs.tertiary.withValues(alpha: 0.35)],
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
                            label: context.tr('new_request'),
                            color: cs.tertiary,
                            icon: Icons.receipt_long_outlined,
                          ),
                          const Spacer(),
                          Text(context.formatPrice(productPrice),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 48, height: 48,
                              color: cs.surfaceContainerHighest,
                              child: productImage.isNotEmpty
                                  ? CachedNetworkImage(imageUrl: productImage, fit: BoxFit.cover, width: 48, height: 48)
                                  : Icon(Icons.image, size: 20, color: cs.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(productName,
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (buyerName.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(buyerName,
                                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
                      const SizedBox(height: 10),
                      if (buyerPhone.isNotEmpty)
                        _infoRow(cs, Icons.phone_outlined, context.tr('phone'), buyerPhone),
                      if (hasAddr) ...[
                        const SizedBox(height: 2),
                        _infoRow(cs, Icons.place_outlined, context.tr('delivery_address'),
                            '${addr['region'] ?? ''}${(addr['region'] as String? ?? '').isNotEmpty && (addr['district'] as String? ?? '').isNotEmpty ? ', ' : ''}${addr['district'] ?? ''}'),
                        if ((addr['ward'] as String? ?? '').isNotEmpty)
                          _infoRow(cs, Icons.holiday_village_outlined, context.tr('ward'), addr['ward'] as String? ?? ''),
                        if ((addr['street'] as String? ?? '').isNotEmpty)
                          _infoRow(cs, Icons.streetview_outlined, context.tr('street_label'), addr['street'] as String? ?? ''),
                        if (addr['landmarks'] != null && (addr['landmarks'] as String).isNotEmpty)
                          _infoRow(cs, Icons.landscape_outlined, context.tr('landmarks'), addr['landmarks'] as String? ?? ''),
                      ],
                      const SizedBox(height: 12),
                      Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
                      const SizedBox(height: 12),
                      DsTextField(
                        controller: _shippingCostCtrl,
                        label: context.tr('enter_shipping_cost'),
                        hint: 'TZS 0',
                        prefixIcon: Icons.monetization_on_outlined,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 14),
                      DsButton(
                        label: _quotingTxId == txId ? context.tr('sending_label') : context.tr('send_shipping_to_buyer'),
                        icon: Icons.send_rounded,
                        loading: _quotingTxId == txId,
                        onPressed: _quotingTxId == txId
                            ? null
                            : () => _submitQuote(txId, buyerId, productName),
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
