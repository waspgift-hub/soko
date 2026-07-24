import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../services/receipt_pdf_service.dart';
import '../../widgets/order_timeline.dart';
import '../../models/transaction_model.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../widgets/google_loading.dart';

class ReceiptScreen extends StatefulWidget {
  final String orderId;
  const ReceiptScreen({super.key, required this.orderId});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  String _lang = 'sw'; // sw or en

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('receipt')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Text(_lang == 'sw' ? 'EN' : 'SW', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary, fontSize: 14)),
            onPressed: () => setState(() => _lang = _lang == 'sw' ? 'en' : 'sw'),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [cs.primary.withValues(alpha: 0.05), cs.surface, cs.secondary.withValues(alpha: 0.05)],
          ),
        ),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('transactions').doc(widget.orderId).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: GoogleLoading());
            final d = snap.data!.data() as Map<String, dynamic>?;
            if (d == null) return Center(child: Text(context.tr('order_not_found'), style: TextStyle(color: cs.error)));

            final status = d['status'] as String? ?? 'pending';
            final productName = d['productName'] as String? ?? context.tr('product');
            final productDescription = d['productDescription'] as String? ?? d['description'] as String? ?? '';
            final productDetails = d['productDetails'] as String? ?? '';
            final price = (d['productPrice'] ?? 0).toDouble();
            final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
            final platformFee = (d['platformFee'] as num?)?.toDouble() ?? 0;
            final mongikeFee = (d['mongikeFee'] as num?)?.toDouble() ?? 180;
            final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? (price + shippingCost + platformFee + mongikeFee);
            final buyerName = d['buyerName'] as String? ?? '';
            final sellerName = d['sellerName'] as String? ?? '';
            final buyerPhone = d['buyerPhone'] as String? ?? '';
            final sellerPhone = d['sellerPhone'] as String? ?? '';
            final sellerLocation = d['sellerLocation'] as String? ?? d['sellerShopLocation'] as String? ?? '';
            final deliveryAddress = d['deliveryAddress'] as Map<String, dynamic>?;
            final dispatchProof = d['dispatchProof'] as Map<String, dynamic>?;
            final createdAt = d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : DateTime.now();
            final txStatus = MarketplaceTransaction.parseStatus(status);
            final productImage = d['productImage'] as String? ?? '';
            final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';
            final transactionReference = d['transactionReference'] as String? ?? d['transactionId'] as String?;
            final courierName = d['courierName'] as String?;
            final driverPhone = d['driverPhone'] as String?;
            final trackingNumber = d['trackingNumber'] as String?;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 20, 16, 32),
              child: _buildReceiptCard(context, cs, d, status, productName, productDescription, productDetails,
                  price, shippingCost, platformFee, mongikeFee, totalAmount,
                  buyerName, sellerName, buyerPhone, sellerPhone, sellerLocation,
                  deliveryAddress, dispatchProof, createdAt, txStatus,
                  productImage, paymentMethod, transactionReference,
                  courierName, driverPhone, trackingNumber),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReceiptCard(
    BuildContext context, ColorScheme cs, Map<String, dynamic> d,
    String status, String productName, String productDescription, String productDetails,
    double price, double shippingCost, double platformFee, double mongikeFee, double totalAmount,
    String buyerName, String sellerName, String buyerPhone, String sellerPhone, String sellerLocation,
    Map<String, dynamic>? deliveryAddress, Map<String, dynamic>? dispatchProof,
    DateTime createdAt, TransactionStatus txStatus, String productImage,
    String paymentMethod, String? transactionReference,
    String? courierName, String? driverPhone, String? trackingNumber,
  ) {
    final loc = _lang == 'sw' ? Locale('sw') : Locale('en');
    final nf = NumberFormat('#,###', 'en');

    // Build timeline steps for QR
    final steps = _getTimelineSteps(status);

    // Seller receives = price - platformFee (what seller actually gets)
    final sellerReceives = price - platformFee;

    // QR data as JSON string
    final qrData = jsonEncode({
      'type': 'soko_vibe_receipt',
      'orderId': widget.orderId,
      'lang': _lang,
      'date': createdAt.toIso8601String(),
      'product': {
        'name': productName,
        'description': productDescription,
        'details': productDetails,
        'price': price,
        'image': productImage,
      },
      'seller': {
        'name': sellerName,
        'phone': sellerPhone,
        'location': sellerLocation,
      },
      'buyer': {
        'name': buyerName,
        'phone': buyerPhone,
      },
      'payment': {
        'total': totalAmount,
        'productPrice': price,
        'shippingCost': shippingCost,
        'commission': platformFee,
        'processingFee': mongikeFee,
        'sellerReceives': sellerReceives,
        'method': paymentMethod,
        'reference': transactionReference,
      },
      'delivery': deliveryAddress != null ? {
        'region': deliveryAddress['region'],
        'district': deliveryAddress['district'],
        'street': deliveryAddress['street'],
        'landmarks': deliveryAddress['landmarks'],
      } : null,
      'status': status,
      'timeline': steps,
    });

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: cs.primary.withValues(alpha: 0.1), blurRadius: 40, offset: const Offset(0, 20)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 60, offset: const Offset(0, 30)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [cs.surface.withValues(alpha: 0.25), cs.surfaceContainerLow.withValues(alpha: 0.15)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, cs, widget.orderId, createdAt),
                const SizedBox(height: 24),
                _buildStatusBadge(context, cs, status),
                const SizedBox(height: 24),
                _divider(cs),
                const SizedBox(height: 20),
                // Product + Seller Details
                _infoSection(cs, _tr(loc, 'order_details', 'Maelezo ya Agizo'), [
                  _infoRow(cs, _tr(loc, 'product', 'Bidhaa'), productName),
                  if (productDescription.isNotEmpty)
                    _infoRow(cs, _tr(loc, 'description', 'Maelezo'), productDescription),
                  if (productDetails.isNotEmpty)
                    _infoRow(cs, _tr(loc, 'details', 'Kinachouzwa'), productDetails),
                  _infoRow(cs, _tr(loc, 'buyer_label', 'Mnunuzi'), buyerName),
                  _infoRow(cs, _tr(loc, 'seller', 'Muuzaji'), sellerName),
                  if (sellerPhone.isNotEmpty)
                    _infoRow(cs, _tr(loc, 'seller_phone', 'Simu ya Muuzaji'), sellerPhone),
                  if (sellerLocation.isNotEmpty)
                    _infoRow(cs, _tr(loc, 'seller_location', 'Duka lipo'), sellerLocation),
                  if (buyerPhone.isNotEmpty)
                    _infoRow(cs, _tr(loc, 'buyer_phone', 'Simu ya Mnunuzi'), buyerPhone),
                ]),
                const SizedBox(height: 16),
                // Delivery Address
                if (deliveryAddress != null) ...[
                  _infoSection(cs, _tr(loc, 'shipping_address', 'Anwani ya Usafirishaji'), [
                    _infoRow(cs, _tr(loc, 'region', 'Mkoa'), deliveryAddress['region'] as String? ?? ''),
                    _infoRow(cs, _tr(loc, 'district', 'Wilaya'), deliveryAddress['district'] as String? ?? ''),
                    _infoRow(cs, _tr(loc, 'street', 'Mtaa'), deliveryAddress['street'] as String? ?? ''),
                    if (deliveryAddress['landmarks'] != null)
                      _infoRow(cs, _tr(loc, 'landmarks', 'Alama'), deliveryAddress['landmarks'] as String),
                  ]),
                  if (courierName != null || driverPhone != null || trackingNumber != null) ...[
                    const SizedBox(height: 16),
                    _infoSection(cs, _tr(loc, 'dispatch_info', 'Maelezo ya Usafirishaji'), [
                      if (courierName != null) _infoRow(cs, _tr(loc, 'courier', 'Mtoa huduma'), courierName!),
                      if (driverPhone != null) _infoRow(cs, _tr(loc, 'driver_phone', 'Simu ya Dereva'), driverPhone!),
                      if (trackingNumber != null) _infoRow(cs, _tr(loc, 'tracking', 'Namba ya kufuatilia'), trackingNumber!),
                    ]),
                  ],
                  const SizedBox(height: 16),
                ],
                // Payment Breakdown
                _infoSection(cs, _tr(loc, 'payment_breakdown', 'Mgawanyo wa Malipo'), [
                  _infoRow(cs, _tr(loc, 'product_price', 'Bei ya Bidhaa'), 'TSh ${nf.format(price.toInt())}'),
                  if (shippingCost > 0)
                    _infoRow(cs, _tr(loc, 'shipping_cost', 'Nauli ya Usafirishaji'), 'TSh ${nf.format(shippingCost.toInt())}', valueColor: cs.secondary),
                  if (platformFee > 0)
                    _infoRow(cs, _tr(loc, 'commission', 'Commission ya Soko Vibe'), 'TSh ${nf.format(platformFee.toInt())}', valueColor: cs.tertiary),
                  _infoRow(cs, _tr(loc, 'mongike_fee_label', 'Ada ya Kuchakata'), 'TSh ${nf.format(mongikeFee.toInt())}', valueColor: cs.tertiary),
                ]),
                const SizedBox(height: 8),
                _divider(cs),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_tr(loc, 'total', 'Jumla'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const Spacer(),
                    Text('TSh ${nf.format(totalAmount.toInt())}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.primary,
                        shadows: [Shadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 8)],
                      )),
                  ],
                ),
                if (sellerReceives > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(_tr(loc, 'seller_gets', 'Muuzaji anapata'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text('TSh ${nf.format(sellerReceives.toInt())}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.successGreen)),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                // QR Code
                _buildQrCode(context, cs, qrData),
                const SizedBox(height: 20),
                // Download Button
                _buildDownloadButton(context, cs, productName, price, shippingCost, platformFee, mongikeFee, sellerReceives,
                    totalAmount, buyerName, sellerName, buyerPhone, sellerPhone, sellerLocation,
                    deliveryAddress, createdAt, status, productImage, paymentMethod, transactionReference,
                    productDescription, productDetails),
                const SizedBox(height: 24),
                // Order Timeline
                Text(_tr(loc, 'order_status', 'Hatua za Agizo'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 12),
                OrderTimeline(
                  status: txStatus,
                  dispatchProof: dispatchProof,
                  courierName: courierName,
                  driverPhone: driverPhone,
                  receiptImageUrl: d['receiptImageUrl'] as String?,
                  trackingNumber: trackingNumber ?? dispatchProof?['trackingNumber'] as String?,
                  shippingCost: shippingCost,
                  deliveryAddress: deliveryAddress,
                  orderId: widget.orderId,
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
                ),
                const SizedBox(height: 24),
                _buildCloseButton(context, cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs, String orderId, DateTime createdAt) {
    return Center(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/soko_vibe_logo.png', height: 32, errorBuilder: (_, __, ___) =>
                Icon(Icons.store, size: 28, color: cs.primary)),
              const SizedBox(width: 8),
              Text('SOKO VIBE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, color: cs.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0.15), cs.primary.withValues(alpha: 0.05)]),
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Icon(Icons.receipt_long, color: cs.primary, size: 28),
          ),
          const SizedBox(height: 10),
          Text(_tr(context, 'receipt_title', 'RISITI YA UNUNUZI'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text('#$orderId', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text('${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, ColorScheme cs, String status) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: _statusColor(status, cs).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _statusColor(status, cs).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_statusIcon(status), size: 16, color: _statusColor(status, cs)),
            const SizedBox(width: 8),
            Text(_statusLabel(status, context), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _statusColor(status, cs))),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCode(BuildContext context, ColorScheme cs, String qrData) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/soko_vibe_logo.png', height: 16, errorBuilder: (_, __, ___) => const SizedBox()),
                const SizedBox(width: 4),
                Text('SOKO VIBE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 1)),
              ],
            ),
            const SizedBox(height: 8),
            QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 160,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: cs.primary),
              dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
            ),
            const SizedBox(height: 8),
            Text(_tr(context, 'scan_to_verify', 'Scan QR kupata taarifa zote'),
                style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton(
    BuildContext context, ColorScheme cs,
    String productName, double price, double shippingCost, double platformFee, double mongikeFee, double sellerReceives,
    double totalAmount, String buyerName, String sellerName, String buyerPhone, String sellerPhone, String sellerLocation,
    Map<String, dynamic>? deliveryAddress, DateTime createdAt, String status, String productImage,
    String paymentMethod, String? transactionReference, String productDescription, String productDetails,
  ) {
    return Center(
      child: _ReceiptDownloadButton(
        orderId: widget.orderId, productName: productName, productImageUrl: productImage,
        price: price, shippingCost: shippingCost, platformFee: platformFee, mongikeFee: mongikeFee,
        sellerReceives: sellerReceives, totalAmount: totalAmount,
        buyerName: buyerName, sellerName: sellerName, buyerPhone: buyerPhone, sellerPhone: sellerPhone,
        sellerLocation: sellerLocation, deliveryAddress: deliveryAddress, createdAt: createdAt,
        status: status, paymentMethod: paymentMethod, transactionReference: transactionReference,
        productDescription: productDescription, productDetails: productDetails,
        lang: _lang,
      ),
    );
  }

  String _tr(context, String key, String fallback) {
    return _lang == 'sw' ? fallback : (context.tr(key) == key ? fallback : context.tr(key));
  }
  String _trLoc(Locale loc, String key, String fallback) => _lang == 'sw' ? fallback : fallback;

  List<String> _getTimelineSteps(String status) {
    final allSteps = ['Order placed', 'Payment received', 'Processing', 'Dispatched', 'Delivered', 'Confirmed'];
    switch (status) {
      case 'pending': return allSteps.take(1).toList();
      case 'awaiting_shipping_quote': return allSteps.take(2).toList();
      case 'paid_escrow_held': case 'escrow_hold': return allSteps.take(3).toList();
      case 'dispatched': return allSteps.take(4).toList();
      case 'delivered': return allSteps.take(5).toList();
      case 'delivery_confirmed': case 'completed': return allSteps;
      case 'failed': return ['Order placed', 'Payment failed'];
      case 'refunded': return ['Order placed', 'Payment received', 'Refunded'];
      default: return [status];
    }
  }

  Widget _divider(ColorScheme cs) {
    return Container(height: 1, decoration: BoxDecoration(
      gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0), cs.primary.withValues(alpha: 0.3), cs.primary.withValues(alpha: 0)]),
    ));
  }

  Widget _buildCloseButton(BuildContext context, ColorScheme cs) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
          ),
          child: Text(context.tr('close'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      ),
    );
  }

  Widget _infoSection(ColorScheme cs, String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.8))),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _infoRow(ColorScheme cs, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? cs.onSurface))),
        ],
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'paid_escrow_held': case 'escrow_hold': return cs.tertiary;
      case 'dispatched': return Colors.orange;
      case 'delivered': case 'delivery_confirmed': case 'completed': return cs.primary;
      case 'failed': case 'refunded': return cs.error;
      default: return cs.onSurfaceVariant;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'paid_escrow_held': case 'escrow_hold': return Icons.lock;
      case 'dispatched': return Icons.local_shipping;
      case 'delivered': case 'delivery_confirmed': case 'completed': return Icons.check_circle;
      case 'failed': return Icons.cancel;
      case 'refunded': return Icons.money_off;
      default: return Icons.hourglass_empty;
    }
  }

  String _statusLabel(String status, BuildContext context) {
    switch (status) {
      case 'awaiting_shipping_quote': return context.tr('awaiting_shipping_quote_label');
      case 'awaiting_payment': return context.tr('awaiting_payment_label');
      case 'paid_escrow_held': case 'escrow_hold': return context.tr('paid_escrow_label');
      case 'dispatched': return context.tr('shipped');
      case 'delivery_confirmed': return context.tr('confirmed');
      case 'delivered': case 'completed': return context.tr('completed');
      case 'disputed': return context.tr('disputed_label');
      case 'refunded': return context.tr('refunded');
      case 'failed': return context.tr('failed');
      default: return context.tr('pending');
    }
  }
}

class _ReceiptDownloadButton extends StatefulWidget {
  final String orderId, productName, productImageUrl;
  final double price, shippingCost, platformFee, mongikeFee, sellerReceives, totalAmount;
  final String buyerName, sellerName, buyerPhone, sellerPhone, sellerLocation;
  final Map<String, dynamic>? deliveryAddress;
  final DateTime createdAt;
  final String status, paymentMethod, productDescription, productDetails;
  final String? transactionReference;
  final String lang;

  const _ReceiptDownloadButton({
    required this.orderId, required this.productName, required this.productImageUrl,
    required this.price, required this.shippingCost, required this.platformFee, required this.mongikeFee,
    required this.sellerReceives, required this.totalAmount,
    required this.buyerName, required this.sellerName, required this.buyerPhone, required this.sellerPhone,
    required this.sellerLocation, this.deliveryAddress, required this.createdAt, required this.status,
    required this.paymentMethod, this.transactionReference,
    required this.productDescription, required this.productDetails, required this.lang,
  });

  @override
  State<_ReceiptDownloadButton> createState() => _ReceiptDownloadButtonState();
}

class _ReceiptDownloadButtonState extends State<_ReceiptDownloadButton> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSw = widget.lang == 'sw';
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isGenerating ? null : _onDownload,
            icon: _isGenerating
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_isGenerating ? (isSw ? 'Inatayarisha...' : 'Generating...') : (isSw ? 'Pakua Risiti' : 'Download Receipt')),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isGenerating ? null : _onShare,
            icon: const Icon(Icons.share, size: 18),
            label: Text(isSw ? 'Shiriki Risiti' : 'Share Receipt'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.secondary,
              side: BorderSide(color: cs.secondary.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onDownload() async {
    setState(() => _isGenerating = true);
    try {
      final pdfBytes = await ReceiptPdfService.generate(
        orderId: widget.orderId, productName: widget.productName,
        productImageUrl: widget.productImageUrl, price: widget.price,
        shippingCost: widget.shippingCost, mongikeFee: widget.mongikeFee,
        totalAmount: widget.totalAmount, buyerName: widget.buyerName,
        sellerName: widget.sellerName, buyerPhone: widget.buyerPhone,
        sellerPhone: widget.sellerPhone, deliveryAddress: widget.deliveryAddress,
        createdAt: widget.createdAt, status: widget.status,
        paymentMethod: widget.paymentMethod, transactionReference: widget.transactionReference,
        platformFee: widget.platformFee, sellerReceives: widget.sellerReceives,
        sellerLocation: widget.sellerLocation, productDescription: widget.productDescription,
        productDetails: widget.productDetails, lang: widget.lang,
      );
      await _saveToDownloads(pdfBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_tr('Failed')}: $e')));
      }
    }
    if (mounted) setState(() => _isGenerating = false);
  }

  Future<void> _onShare() async {
    setState(() => _isGenerating = true);
    try {
      final pdfBytes = await ReceiptPdfService.generate(
        orderId: widget.orderId, productName: widget.productName,
        productImageUrl: widget.productImageUrl, price: widget.price,
        shippingCost: widget.shippingCost, mongikeFee: widget.mongikeFee,
        totalAmount: widget.totalAmount, buyerName: widget.buyerName,
        sellerName: widget.sellerName, buyerPhone: widget.buyerPhone,
        sellerPhone: widget.sellerPhone, deliveryAddress: widget.deliveryAddress,
        createdAt: widget.createdAt, status: widget.status,
        paymentMethod: widget.paymentMethod, transactionReference: widget.transactionReference,
        platformFee: widget.platformFee, sellerReceives: widget.sellerReceives,
        sellerLocation: widget.sellerLocation, productDescription: widget.productDescription,
        productDetails: widget.productDetails, lang: widget.lang,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${widget.orderId}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Soko Vibe Receipt #${widget.orderId}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_tr('Failed')}: $e')));
      }
    }
    if (mounted) setState(() => _isGenerating = false);
  }

  Future<void> _saveToDownloads(Uint8List pdfBytes) async {
    if (Platform.isAndroid) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/receipt_${widget.orderId}.pdf');
      await file.writeAsBytes(pdfBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_tr('Receipt saved')}: ${file.path}'), duration: const Duration(seconds: 4)),
        );
      }
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${widget.orderId}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Soko Vibe Receipt #${widget.orderId}');
    }
  }

  String _tr(String en) => widget.lang == 'sw' ? en : en;
}
