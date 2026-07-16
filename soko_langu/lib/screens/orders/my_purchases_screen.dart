import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../models/transaction_model.dart';
import '../../models/product_receipt.dart';
import '../../services/api_config.dart';
import '../../services/mongike_service.dart';
import '../../services/sms_notification_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/order_timeline.dart';
import '../../utils/phone_utils.dart';
import '../../app/routes.dart';
import 'package:go_router/go_router.dart';

class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key});

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  String? _releasingTxId;
  String? _disputingTxId;
  String? _payingTxId;
  String? _cancellingTxId;

  Future<void> _payForOrder(String txId, Map<String, dynamic> d) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _payingTxId = txId);

    try {
      final productPrice = (d['productPrice'] as num?)?.toDouble() ?? 0;
      final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
      final productName = d['productName'] as String? ?? 'Product';
      final productId = d['productId'] as String? ?? '';
      final sellerId = d['sellerId'] as String? ?? '';
      final sellerName = d['sellerName'] as String? ?? '';

      final result = await MongikeService.initiateMarketplacePayment(
        productPrice: productPrice,
        productName: productName,
        productId: productId,
        sellerId: sellerId,
        sellerName: sellerName,
        email: user.email ?? '',
        phone: d['buyerPhone'] as String? ?? '',
        buyerId: user.uid,
        deliveryType: 'local',
        shippingCost: shippingCost,
        existingTransactionId: txId,
      );

      if (result == null || result['order_id'] == null) {
        final errMsg = result?['error'] as String? ?? 'Failed to initiate payment';
        _showError(errMsg);
        setState(() => _payingTxId = null);
        return;
      }

      if (mounted) _showSuccess('Angalia simu yako — weka PIN kukamilisha malipo.');
    } catch (e) {
      _showError('Payment error: $e');
    }

    setState(() => _payingTxId = null);
  }

  Future<void> _confirmDelivery(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _releasingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/release'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess(context.tr('delivery_confirmed_msg'));

        final txDoc = await FirebaseFirestore.instance.collection('transactions').doc(txId).get();
        if (txDoc.exists) {
          final tx = txDoc.data()!;
          final sellerId = tx['sellerId'] as String? ?? '';
          final grandTotal = ((tx['totalAmount'] as num?)?.toDouble() ?? 0);
          if (sellerId.isNotEmpty) {
            final sellerDoc = await FirebaseFirestore.instance.collection('users').doc(sellerId).get();
            final sellerPhone = sellerDoc.data()?['phone'] as String? ?? '';
            if (sellerPhone.isNotEmpty) {
              SmsNotificationService.notifyEscrowReleased(
                sellerPhone: sellerPhone,
                orderId: txId,
                grandTotal: grandTotal.toStringAsFixed(0),
              );
            }
          }
        }
      } else {
        _showError(result['error'] ?? context.tr('confirm_failed_msg'));
      }
    } catch (e) {
      _showError('${context.tr('confirm_failed_msg')}: $e');
    }

    setState(() => _releasingTxId = null);
  }

  Future<void> _raiseDispute(String txId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fungua Mgogoro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Je, hukupata bidhaa? Eleza sababu na tutakagua.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Sababu',
                hintText: 'Sijapata mzigo...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fungua Mgogoro')),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _disputingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'orderId': txId,
          'userId': user.uid,
          'reason': reasonCtrl.text,
          'evidenceUrls': [],
        }),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess('Mgogoro umefunguliwa. Admin atakagua.');
      } else {
        _showError(result['error'] ?? 'Failed to raise dispute');
      }
    } catch (e) {
      _showError('Error: $e');
    }

    setState(() => _disputingTxId = null);
  }

  Future<void> _cancelOrder(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghairi Oda?'),
        content: const Text('Hii itarudisha hela yako yote kupitia Mongike. Hakikisha hujapokea mzigo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Ndiyo, Ghairi')),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _cancellingTxId = txId);

    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );

      final result = jsonDecode(resp.body);

      if (resp.statusCode == 200 && result['success'] == true) {
        _showSuccess('Oda imeghairiwa. Hela yako imerudishwa.');
      } else {
        _showError(result['error'] ?? 'Failed to cancel order');
      }
    } catch (e) {
      _showError('Error: $e');
    }

    setState(() => _cancellingTxId = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('my_purchases'))),
        body: Center(child: Text(context.tr('login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('my_purchases')),
        actions: [
          TextButton.icon(
            onPressed: () => context.go(AppRoutes.home),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: Text(context.tr('home')),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('buyerId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('no_purchases_yet'),
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          final docs = snap.data!.docs;
          docs.sort((a, b) {
            final ta = (a.data() as Map)['createdAt'];
            final tb = (b.data() as Map)['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });

          if (docs.isEmpty) {
            return Center(child: Text(context.tr('no_purchases_yet')));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final status = d['status'] as String? ?? 'pending';
              final productName = d['productName'] as String? ?? 'Product';
              final price = (d['productPrice'] ?? 0).toDouble();
              final dispatchProof = d['dispatchProof'] as Map<String, dynamic>?;
              final txStatus = MarketplaceTransaction.parseStatus(status);

              IconData statusIcon;
              Color statusColor;
              String statusText;
              bool canConfirm = false;
              bool canDispute = false;
              bool canPay = false;
              bool canCancel = false;
              double totalForPayment = price;

              switch (status) {
                case 'awaiting_shipping_quote':
                  statusIcon = Icons.receipt_long;
                  statusColor = cs.tertiary;
                  statusText = 'Inasuburi gharama ya usafirishaji';
                  break;
                case 'awaiting_payment':
                  statusIcon = Icons.pending;
                  statusColor = Colors.orange;
                  final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
                  totalForPayment = price + shippingCost;
                  statusText = 'Gharama ya usafirishaji imetolewa — lipa sasa';
                  canPay = true;
                  break;
                case 'escrow_hold':
                case 'paid_escrow_held':
                  statusIcon = Icons.lock;
                  statusColor = cs.tertiary;
                  statusText = 'Imelipwa — inasubiri muuzaji atume';
                  canDispute = true;
                  canCancel = true;
                  break;
                case 'dispatched':
                  statusIcon = Icons.local_shipping;
                  statusColor = Colors.orange;
                  statusText = 'Imesafirishwa — thibitisha upokeaji';
                  canConfirm = true;
                  canDispute = true;
                  break;
                case 'disputed':
                  statusIcon = Icons.gavel;
                  statusColor = Colors.red;
                  statusText = 'Mgogoro — Admin anakagua';
                  break;
                case 'delivery_confirmed':
                  statusIcon = Icons.how_to_vote;
                  statusColor = cs.secondary;
                  statusText = context.tr('confirmed_processing');
                  break;
                case 'delivered':
                  statusIcon = Icons.check_circle;
                  statusColor = cs.primary;
                  statusText = context.tr('completed');
                  break;
                case 'completed':
                  statusIcon = Icons.check_circle;
                  statusColor = cs.primary;
                  statusText = context.tr('completed');
                  break;
                case 'refunded':
                  statusIcon = Icons.money_off;
                  statusColor = cs.error;
                  statusText = context.tr('refunded');
                  break;
                case 'failed':
                  statusIcon = Icons.cancel;
                  statusColor = cs.error;
                  statusText = context.tr('failed');
                  break;
                default:
                  statusIcon = Icons.hourglass_empty;
                  statusColor = cs.onSurfaceVariant.withValues(alpha: 0.6);
                  statusText = context.tr('pending');
              }

              final productReceiptData = d['passengerName'] == null || (d['passengerName'] as String).isEmpty
                  ? ProductReceipt(
                      transactionId: docs[i].id,
                      orderId: docs[i].id,
                      buyerName: d['buyerName'] as String? ?? '',
                      shopName: d['sellerName'] as String? ?? '',
                      productTitle: d['productName'] as String? ?? '',
                      productPrice: (d['productPrice'] as num?)?.toDouble() ?? 0,
                      shippingCost: (d['shippingCost'] as num?)?.toDouble() ?? 0,
                      grandTotal: (d['totalAmount'] as num?)?.toDouble() ?? price,
                      paymentMethod: d['paymentMethod'] as String? ?? '',
                      timestamp: d['createdAt'] is Timestamp
                          ? (d['createdAt'] as Timestamp).toDate()
                          : DateTime.now(),
                      escrowStatus: _escrowLabel(status),
                    )
                  : null;

              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: GestureDetector(
                    onTap: () => context.push('/receipt/${docs[i].id}'),
                    child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            context.formatPrice(price),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(productName, style: const TextStyle(fontSize: 15)),
                      if ((d['shippingCost'] as num?)?.toDouble() != null && (d['shippingCost'] as num).toDouble() > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Usafirishaji: ${context.formatPrice((d['shippingCost'] as num).toDouble())}',
                            style: TextStyle(fontSize: 12, color: cs.secondary),
                          ),
                        ),
                      if (d['buyerPhone'] != null &&
                          (d['buyerPhone'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${context.tr('phone_label')}${PhoneUtils.formatForDisplay(d['buyerPhone'] as String)}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (dispatchProof != null && dispatchProof['trackingNumber'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Tracking: ${dispatchProof['trackingNumber'] ?? '-'}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 12),
                      OrderTimeline(
                        status: txStatus,
                        dispatchProof: dispatchProof,
                        courierName: d['courierName'] as String?,
                        driverPhone: d['driverPhone'] as String?,
                        receiptImageUrl: d['receiptImageUrl'] as String?,
                        trackingNumber: d['trackingNumber'] as String? ?? dispatchProof?['trackingNumber'] as String?,
                        shippingCost: (d['shippingCost'] as num?)?.toDouble(),
                        deliveryAddress: d['deliveryAddress'] as Map<String, dynamic>?,
                        orderId: docs[i].id,
                        passengerName: d['passengerName'] as String?,
                        busName: d['busName'] as String?,
                        receiptNumber: d['receiptNumber'] as String?,
                        departureTime: d['departureTime'] as String?,
                        arrivalTime: d['arrivalTime'] as String?,
                        originStation: d['originStation'] as String?,
                        destinationStation: d['destinationStation'] as String?,
                        travelDate: d['travelDate'] as String?,
                        travelDay: d['travelDay'] as String?,
                        shippingFare: (d['shippingFare'] as num?)?.toDouble(),
                        plateNumber: d['plateNumber'] as String?,
                        productReceipt: productReceiptData,
                      ),
                      if (canPay || canConfirm || canDispute)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              if (canPay)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _payingTxId == docs[i].id ? null : () => _payForOrder(docs[i].id, d),
                                    icon: _payingTxId == docs[i].id
                                        ? const SizedBox(width: 16, height: 16, child: GoogleLoading(size: 16, strokeWidth: 2))
                                        : const Icon(Icons.payment, size: 18),
                                    label: Text(_payingTxId == docs[i].id ? 'Inalipa...' : 'Lipa ${context.formatPrice(totalForPayment)}'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.surface,
                                    ),
                                  ),
                                ),
                              if (canConfirm)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _releasingTxId == docs[i].id
                                        ? null
                                        : () => _confirmDelivery(docs[i].id),
                                    icon: _releasingTxId == docs[i].id
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: GoogleLoading(size: 16, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.verified, size: 18),
                                    label: Text(
                                      _releasingTxId == docs[i].id
                                          ? context.tr('processing')
                                          : context.tr('confirm_receipt'),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.surface,
                                    ),
                                  ),
                                ),
                              if ((canConfirm || canPay) && canDispute) const SizedBox(width: 8),
                              if (canDispute)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _disputingTxId == docs[i].id
                                        ? null
                                        : () => _raiseDispute(docs[i].id),
                                    icon: _disputingTxId == docs[i].id
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: GoogleLoading(size: 16, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.gavel, size: 18),
                                    label: Text(
                                      _disputingTxId == docs[i].id
                                          ? context.tr('processing')
                                          : 'Sijapata mzigo',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cs.error,
                                      side: BorderSide(color: cs.error),
                                    ),
                                  ),
                                ),
                              if (canCancel) const SizedBox(width: 8),
                              if (canCancel)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _cancellingTxId == docs[i].id
                                        ? null
                                        : () => _cancelOrder(docs[i].id),
                                    icon: _cancellingTxId == docs[i].id
                                        ? const SizedBox(
                                            width: 16, height: 16,
                                            child: GoogleLoading(size: 16, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.money_off, size: 18),
                                    label: Text(
                                      _cancellingTxId == docs[i].id
                                          ? context.tr('processing')
                                          : 'Ghairi & Rudishiwa',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cs.primary,
                                      side: BorderSide(color: cs.primary),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                    ),
                  ),
                    ),
                  ),
                );
              );


  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.primary));
  }

  String _escrowLabel(String status) {
    switch (status) {
      case 'paid_escrow_held':
      case 'escrow_hold':
        return 'Secured in Escrow';
      case 'dispatched':
        return 'Dispatched';
      case 'delivered':
      case 'delivery_confirmed':
      case 'completed':
        return 'Delivered & Completed';
      case 'failed':
        return 'Failed';
      case 'refunded':
        return 'Refunded';
      default:
        return 'Pending';
    }
  }
}
