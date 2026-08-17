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
import '../../widgets/ds/ds.dart';

class SellerQuoteScreen extends StatefulWidget {
  const SellerQuoteScreen({super.key});

  @override
  State<SellerQuoteScreen> createState() => _SellerQuoteScreenState();
}

class _SellerQuoteScreenState extends State<SellerQuoteScreen> {
  final Map<String, TextEditingController> _costCtrls = {};
  final Map<String, bool> _submitting = {};

  @override
  void dispose() {
    for (final c in _costCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(String txId) {
    return _costCtrls.putIfAbsent(txId, () => TextEditingController());
  }

  Future<void> _submitQuote(String txId, String buyerId, String productName) async {
    final ctrl = _ctrlFor(txId);
    final cost = double.tryParse(ctrl.text.trim());
    if (cost == null || cost <= 0) {
      _showError(context.tr('enter_valid_shipping_cost'));
      return;
    }

    setState(() => _submitting[txId] = true);
    HapticFeedback.lightImpact();

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        _showError(context.tr('login_required'));
        setState(() => _submitting[txId] = false);
        return;
      }

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

      if (resp.statusCode == 200) {
        _showSuccess(context.tr('shipping_cost_submitted'));
        ctrl.clear();
      } else {
        _showError(context.tr('quote_sync_warning'));
      }
    } catch (_) {
      _showError(context.tr('quote_sync_warning'));
    }

    if (mounted) setState(() => _submitting[txId] = false);
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
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('sellerId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'awaiting_shipping_quote')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${context.tr('error')}: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading());
          }

          final docs = snap.data!.docs
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final d = docs[i].data() as Map<String, dynamic>;
                final txId = docs[i].id;
                return _OrderQuoteCard(
                  data: d,
                  txId: txId,
                  costController: _ctrlFor(txId),
                  isSubmitting: _submitting[txId] == true,
                  onSubmit: () => _submitQuote(txId, d['buyerId'] ?? '', d['productName'] ?? ''),
                );
              },
            ),
          );
        },
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

class _OrderQuoteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String txId;
  final TextEditingController costController;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const _OrderQuoteCard({
    required this.data,
    required this.txId,
    required this.costController,
    required this.onSubmit,
    this.isSubmitting = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final productName = data['productName'] ?? context.tr('product');
    final productImage = data['productImage'] as String? ?? '';
    final productPrice = (data['productPrice'] as num?)?.toDouble() ?? 0;
    final buyerName = data['buyerName'] ?? '';
    final buyerPhone = data['buyerPhone'] as String? ?? '';
    final deliveryType = data['deliveryType'] as String? ?? 'local';
    final region = data['region'] as String? ?? '';
    final district = data['district'] as String? ?? '';
    final ward = data['ward'] as String? ?? '';
    final street = data['street'] as String? ?? '';
    final landmarks = data['landmarks'] as String? ?? '';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final addr = [region, district, ward, street].where((s) => s.isNotEmpty).join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DsCard(
        radius: 20,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('new_request'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.primary),
                  ),
                  const Spacer(),
                  if (createdAt != null)
                    Text(
                      _formatDate(context, createdAt),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Product ──
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 64, height: 64,
                          color: cs.surfaceContainerHighest,
                          child: productImage.isNotEmpty
                              ? CachedNetworkImage(imageUrl: productImage, fit: BoxFit.cover, width: 64, height: 64)
                              : Icon(Icons.image, size: 28, color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(productName,
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                              context.formatPrice(productPrice),
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: cs.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),

                  // ── Buyer Info ──
                  _SectionTitle(icon: Icons.person_outline, title: context.tr('buyer_info', 'Mnunuzi')),
                  const SizedBox(height: 10),
                  if (buyerName.isNotEmpty)
                    _DetailRow(icon: Icons.badge_outlined, label: context.tr('name'), value: buyerName),
                  if (buyerPhone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _DetailRow(icon: Icons.phone_outlined, label: context.tr('phone'), value: buyerPhone),
                  ],

                  const SizedBox(height: 16),
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),

                  // ── Delivery Address ──
                  _SectionTitle(icon: Icons.location_on_outlined, title: context.tr('delivery_address')),
                  const SizedBox(height: 10),
                  if (addr.isNotEmpty)
                    _DetailRow(icon: Icons.place_outlined, label: '', value: addr),
                  if (ward.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _DetailRow(icon: Icons.holiday_village_outlined, label: context.tr('ward'), value: ward),
                  ],
                  if (landmarks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _DetailRow(icon: Icons.landscape_outlined, label: context.tr('landmarks'), value: landmarks),
                  ],
                  if (addr.isEmpty && ward.isEmpty && landmarks.isEmpty)
                    Text(
                      context.tr('no_address_provided', 'Hakuna anwani iliyotolewa'),
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),

                  const SizedBox(height: 16),
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),

                  // ── Delivery Type ──
                  _SectionTitle(icon: Icons.local_shipping_outlined, title: context.tr('delivery_type', 'Aina ya Usafirishaji')),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          deliveryType == 'local' ? Icons.location_city : Icons.flight_takeoff,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          deliveryType == 'local' ? context.tr('local_delivery') : context.tr('upcountry_delivery'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Shipping Cost Input ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.15), width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('enter_shipping_cost'),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('set_cost_note', 'Weka gharama ya usafirishaji kwa mnunuzi'),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        DsTextField(
                          controller: costController,
                          hint: 'TZS 0',
                          prefixIcon: Icons.monetization_on_outlined,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: DsButton(
                            label: isSubmitting ? context.tr('sending_label') : context.tr('send_shipping_to_buyer'),
                            icon: Icons.send_rounded,
                            loading: isSubmitting,
                            onPressed: isSubmitting ? null : onSubmit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return context.tr('now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays == 1) return context.tr('yesterday');
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text(
                value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
