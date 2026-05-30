import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/order_service.dart';
import '../../services/review_service.dart';
import '../../services/mongike_service.dart';
import '../../models/order_model.dart';
import '../../extensions/context_tr.dart';

import '../../widgets/google_loading.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final OrderService _orderService = OrderService();
  bool _showReceived = false;
  final Set<String> _promptedOrders = {};

  Future<void> _autoPromptReview(List<Order> orders) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    for (final order in orders) {
      if (order.status != OrderStatus.delivered) continue;
      if (order.buyerId != uid) continue;
      if (_promptedOrders.contains(order.id)) continue;
      _promptedOrders.add(order.id);
      for (final item in order.items) {
        if (order.reviewedProductIds.contains(item.productId)) continue;
        if (!mounted) return;
        final reviewed = await _showReviewDialog(item.productId, order.id, item.name);
        if (reviewed && mounted) setState(() {});
        break;
      }
    }
  }

  Future<bool> _showReviewDialog(String productId, String orderId, String productName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    double rating = 5;
    final commentController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('write_review')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(productName, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () => setDialogState(() => rating = i + 1),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: context.tr('share_experience'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('later')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('submit')),
            ),
          ],
        ),
      ),
    );

    if (result != true || commentController.text.trim().isEmpty) return false;

    try {
      await ReviewService().addReview(
        productId: productId,
        rating: rating,
        comment: commentController.text.trim(),
        orderId: orderId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('review_submitted'))),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('error')}: $e")),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showReceived
              ? context.tr('received_orders')
              : context.tr('my_orders'),
        ),
        actions: [
          ToggleButtons(
            isSelected: [!_showReceived, _showReceived],
            onPressed: (i) => setState(() => _showReceived = i == 1),
            borderRadius: BorderRadius.circular(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 30),
            textStyle: const TextStyle(fontSize: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(context.tr('my_orders')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(context.tr('received')),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<Order>>(
          stream: _showReceived
              ? _orderService.getReceivedOrders()
              : _orderService.getMyOrders(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const GoogleLoadingPage();
            }
            final orders = snapshot.data ?? [];
            WidgetsBinding.instance.addPostFrameCallback((_) => _autoPromptReview(orders));
            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _showReceived
                          ? context.tr('no_received_orders')
                          : context.tr('no_orders'),
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final isSeller = order.sellerId == uid;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${context.tr('order')} #${order.id.substring(0, 8)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Chip(
                                  label: Text(
                                    order.statusText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  backgroundColor: _statusColor(order.status),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (order.paymentMethod == 'Mongike')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.account_balance_wallet,
                                          size: 12,
                                          color: const Color(0xFF6C63FF),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Mongike',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6C63FF),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_showReceived)
                          Text(
                            '${context.tr('buyer')}: ${order.buyerName}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 8),
                        ...order.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    "${item.name} x${item.quantity} - ${context.currencySymbol()}${item.totalPrice.toStringAsFixed(0)}",
                                  ),
                                ),
                                if (!_showReceived &&
                                    _canReview(order.status) &&
                                    !order.reviewedProductIds.contains(
                                      item.productId,
                                    ))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _ReviewButton(
                                      productId: item.productId,
                                      orderId: order.id,
                                      productName: item.name,
                                      onReviewed: () => setState(() {}),
                                    ),
                                  ),
                                if (!_showReceived &&
                                    order.reviewedProductIds.contains(
                                      item.productId,
                                    ))
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${context.tr('total')}:",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${context.currencySymbol()}${order.totalAmount.toStringAsFixed(0)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        if (order.paymentMethod != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.payment,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${context.tr('payment')}: ${order.paymentMethodName ?? order.paymentMethod}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "${context.tr('ordered')}: ${_formatDate(order.createdAt)}",
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isSeller &&
                            order.status == OrderStatus.pending) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _confirmPayment(order.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: Text(
                                context.tr('confirm_received_payment'),
                              ),
                            ),
                          ),
                        ],
                        if (isSeller &&
                            order.status == OrderStatus.confirmed) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _updateStatus(order.id, OrderStatus.shipped),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.local_shipping, size: 18),
                              label: Text(context.tr('mark_shipped')),
                            ),
                          ),
                        ],
                        if (isSeller &&
                            order.status == OrderStatus.shipped) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _updateStatus(
                                order.id,
                                OrderStatus.delivered,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: Text(context.tr('mark_delivered')),
                            ),
                          ),
                        ],
                        if (order.status == OrderStatus.pending && !isSeller)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info,
                                  size: 14,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    context.tr('waiting_seller_confirm'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (order.paymentMethod == 'Mongike' && order.status == OrderStatus.pending) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _checkMongikePayment(order.id),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF6C63FF),
                                side: const BorderSide(color: Color(0xFF6C63FF)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Check Mongike Payment Status'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmPayment(String orderId) async {
    try {
      await _orderService.updateOrderStatus(orderId, OrderStatus.confirmed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('payment_confirmed_success'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${context.tr('confirm_failed')} $e")),
        );
      }
    }
  }

  Future<void> _updateStatus(String orderId, OrderStatus status) async {
    try {
      await _orderService.updateOrderStatus(orderId, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order ${status.toString().split('.').last}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _checkMongikePayment(String orderId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final result = await MongikeService.checkPaymentStatus(orderId);

      if (!mounted) return;
      Navigator.pop(context);

      if (result['success'] == true && result['paid'] == true) {
        await _orderService.confirmMongikePayment(orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Mongike payment confirmed! Order updated.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment status: ${result['status']}. Mnunuzi bado hajalipa.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check payment: $e')),
        );
      }
    }
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.processing:
        return Colors.blueGrey;
      case OrderStatus.shipped:
        return Colors.indigo;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  String _formatDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  bool _canReview(OrderStatus status) {
    return status == OrderStatus.confirmed ||
        status == OrderStatus.processing ||
        status == OrderStatus.shipped ||
        status == OrderStatus.delivered;
  }
}

class _ReviewButton extends StatefulWidget {
  final String productId;
  final String orderId;
  final String productName;
  final VoidCallback onReviewed;

  const _ReviewButton({
    required this.productId,
    required this.orderId,
    required this.productName,
    required this.onReviewed,
  });

  @override
  State<_ReviewButton> createState() => _ReviewButtonState();
}

class _ReviewButtonState extends State<_ReviewButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton.icon(
              onPressed: () async {
                setState(() => _loading = true);
                final parent = context.findAncestorStateOfType<_MyOrdersScreenState>();
                if (parent != null) {
                  await parent._showReviewDialog(widget.productId, widget.orderId, widget.productName);
                }
                if (mounted) {
                  setState(() => _loading = false);
                  widget.onReviewed();
                }
              },
              icon: const Icon(Icons.star_border, size: 14),
              label: Text(
                context.tr('rate'),
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
    );
  }
}

