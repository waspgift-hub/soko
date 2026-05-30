import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../extensions/context_tr.dart';
import '../../services/order_service.dart';
import '../../models/order_model.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final OrderService _orderService = OrderService();
  Order? _order;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await _orderService.getOrderById(widget.orderId);
    if (mounted) setState(() { _order = order; _loading = false; });
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending: return Colors.orange;
      case OrderStatus.confirmed: return Colors.blue;
      case OrderStatus.processing: return Colors.blueGrey;
      case OrderStatus.shipped: return Colors.indigo;
      case OrderStatus.delivered: return Colors.green;
      case OrderStatus.cancelled: return Colors.red;
    }
  }

  Future<void> _confirmDelivery() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('mark_delivered')),
        content: Text('Unathibitisha umepokea bidhaa hii? Malipo yatatolewa kwa muuzaji.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('yes'), style: const TextStyle(color: Colors.green))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processing = true);
    try {
      await _orderService.confirmDelivery(widget.orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Umethibitisha kupokea! Malipo yametolewa kwa muuzaji.'), backgroundColor: Colors.green),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imeshindwa: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _markShipped() async {
    setState(() => _processing = true);
    try {
      await _orderService.updateOrderStatus(widget.orderId, OrderStatus.shipped);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agizo limewekwa kama Imesafirishwa'), backgroundColor: Colors.green),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imeshindwa: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isBuyer = _order?.buyerId == currentUser?.uid;
    final isSeller = _order?.sellerId == currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: Text('${context.tr('order')} #${widget.orderId.substring(0, 8)}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? Center(child: Text(context.tr('no_orders')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(context.tr('status'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                Chip(
                                  label: Text(_order!.statusText, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  backgroundColor: _statusColor(_order!.status),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _detailRow(context.tr('ordered'), _formatDate(_order!.createdAt)),
                            if (_order!.paymentMethod != null)
                              _detailRow(context.tr('payment_method'), _order!.paymentMethod!),
                            if (_order!.trackingNumber != null)
                              _detailRow('Tracking', _order!.trackingNumber!),
                            if (_order!.paymentNumber != null && _order!.paymentNumber!.isNotEmpty)
                              _detailRow(context.tr('phone'), _order!.paymentNumber!),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.tr('products'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 8),
                            ..._order!.items.map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('${item.name} x${item.quantity}', style: const TextStyle(fontSize: 14)),
                                  ),
                                  Text('${context.currencySymbol()}${item.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(context.tr('total'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('${context.currencySymbol()}${_order!.totalAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isBuyer ? context.tr('seller') : context.tr('buyer'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 8),
                            _detailRow(isBuyer ? context.tr('seller') : context.tr('buyer'), isBuyer ? _order!.sellerId : _order!.buyerName),
                            if (_order!.shippingAddress != null)
                              _detailRow('Shipping', _order!.shippingAddress!),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStatusTimeline(),
                    const SizedBox(height: 16),
                    if (isBuyer && (_order!.status == OrderStatus.shipped || _order!.status == OrderStatus.confirmed))
                      _buildBuyerActions(),
                    if (isSeller && (_order!.status == OrderStatus.pending || _order!.status == OrderStatus.confirmed))
                      _buildSellerActions(),
                    if (_order!.status == OrderStatus.delivered && isBuyer)
                      _buildReviewPrompt(),
                  ],
                ),
    );
  }

  Widget _buildBuyerActions() {
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text('Thibitisha Kupokea', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[800])),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ukipokea bidhaa, bonyeza hapa. Malipo yatatolewa moja kwa moja kwa muuzaji.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _confirmDelivery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _processing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle),
                label: Text(_processing ? context.tr('processing') : context.tr('mark_delivered')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerActions() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text('Safirisha Bidhaa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[800])),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Umepokea malipo? Bonyeza hapa kuonyesha umesafirisha bidhaa.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _markShipped,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _processing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.local_shipping),
                label: Text(_processing ? context.tr('processing') : context.tr('mark_shipped')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPrompt() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber[700]),
                const SizedBox(width: 8),
                Text('Acha Maoni', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber[800])),
              ],
            ),
            const SizedBox(height: 8),
            Text('Umepokea bidhaa. Acha maoni yako kusaidia wengine.', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.amber[700]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: Icon(Icons.star, color: Colors.amber[700]),
                label: Text(context.tr('write_review'), style: TextStyle(color: Colors.amber[800])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    final statuses = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.processing,
      OrderStatus.shipped,
      OrderStatus.delivered,
    ];
    final currentIdx = statuses.indexOf(_order!.status);
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('status'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ...List.generate(statuses.length, (i) {
              final done = i <= currentIdx;
              final last = i == statuses.length - 1;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Column(
                        children: [
                          Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: done ? _statusColor(statuses[i]) : cs.outlineVariant,
                            ),
                            child: done ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
                          ),
                          if (!last)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: done ? _statusColor(statuses[i]) : cs.outlineVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: EdgeInsets.only(bottom: last ? 0 : 16),
                      child: Text(statuses[i].toString().split('.').last, style: TextStyle(fontSize: 13, color: done ? cs.onSurface : cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
