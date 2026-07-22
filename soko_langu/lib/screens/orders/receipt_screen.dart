import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/receipt_pdf_service.dart';
import '../../widgets/order_timeline.dart';
import '../../models/transaction_model.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class ReceiptScreen extends StatelessWidget {
  final String orderId;
  const ReceiptScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('receipt')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.05),
              cs.surface,
              cs.secondary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('transactions').doc(orderId).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: GoogleLoading());
            }

            final d = snap.data!.data() as Map<String, dynamic>?;
            if (d == null) {
              return Center(child: Text(context.tr('order_not_found'), style: TextStyle(color: cs.error)));
            }

            final status = d['status'] as String? ?? 'pending';
            final productName = d['productName'] as String? ?? context.tr('product');
            final price = (d['productPrice'] ?? 0).toDouble();
            final shippingCost = (d['shippingCost'] as num?)?.toDouble() ?? 0;
            final mongikeFee = (d['mongikeFee'] as num?)?.toDouble() ?? 180;
            final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? (price + shippingCost + mongikeFee);
            final buyerName = d['buyerName'] as String? ?? '';
            final sellerName = d['sellerName'] as String? ?? '';
            final buyerPhone = d['buyerPhone'] as String? ?? '';
            final sellerPhone = d['sellerPhone'] as String? ?? '';
            final deliveryAddress = d['deliveryAddress'] as Map<String, dynamic>?;
            final dispatchProof = d['dispatchProof'] as Map<String, dynamic>?;
            final createdAt = d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : DateTime.now();
            final txStatus = MarketplaceTransaction.parseStatus(status);
            final productImage = d['productImage'] as String? ?? '';
            final paymentMethod = d['paymentMethod'] as String? ?? 'Mongike';
            final transactionReference = d['transactionReference'] as String? ?? d['transactionId'] as String?;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 20, 16, 32),
              child: _build3DGlassCard(context, cs, d, status, productName, price, shippingCost, mongikeFee,
                  totalAmount, buyerName, sellerName, buyerPhone, sellerPhone,
                  deliveryAddress, dispatchProof, createdAt, txStatus,
                  productImage, paymentMethod, transactionReference),
            );
          },
        ),
      ),
    );
  }

  Widget _build3DGlassCard(
    BuildContext context,
    ColorScheme cs,
    Map<String, dynamic> d,
    String status,
    String productName,
    double price,
    double shippingCost,
    double mongikeFee,
    double totalAmount,
    String buyerName,
    String sellerName,
    String buyerPhone,
    String sellerPhone,
    Map<String, dynamic>? deliveryAddress,
    Map<String, dynamic>? dispatchProof,
    DateTime createdAt,
    TransactionStatus txStatus,
    String productImage,
    String paymentMethod,
    String? transactionReference,
  ) {
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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.surface.withValues(alpha: 0.25),
                    cs.surfaceContainerLow.withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, cs, orderId, createdAt),
                  const SizedBox(height: 24),
                  _buildStatusBadge(context, cs, status),
                  const SizedBox(height: 24),
                  _divider(cs),
                  const SizedBox(height: 20),
                  _infoSection(cs, context.tr('order_details'), [
                    _infoRow(cs, context.tr('product'), productName),
                    _infoRow(cs, context.tr('buyer_label'), buyerName),
                    _infoRow(cs, context.tr('seller'), sellerName),
                    if (buyerPhone.isNotEmpty) _infoRow(cs, context.tr('buyer_phone'), buyerPhone),
                    if (sellerPhone.isNotEmpty) _infoRow(cs, context.tr('seller_phone'), sellerPhone),
                  ]),
                  const SizedBox(height: 16),
                  if (deliveryAddress != null) ...[
                    _infoSection(cs, context.tr('shipping_address'), [
                      _infoRow(cs, context.tr('region'), deliveryAddress['region'] as String? ?? ''),
                      _infoRow(cs, context.tr('district'), deliveryAddress['district'] as String? ?? ''),
                      _infoRow(cs, context.tr('street'), deliveryAddress['street'] as String? ?? ''),
                      if (deliveryAddress['landmarks'] != null)
                        _infoRow(cs, context.tr('landmarks'), deliveryAddress['landmarks'] as String),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  _infoSection(cs, context.tr('payment_breakdown'), [
                    _infoRow(cs, context.tr('product_price'), context.formatPrice(price)),
                    if (shippingCost > 0) _infoRow(cs, context.tr('shipping_cost'), context.formatPrice(shippingCost), valueColor: cs.secondary),
                    _infoRow(cs, context.tr('mongike_fee_label'), context.formatPrice(mongikeFee), valueColor: cs.tertiary),
                  ]),
                  const SizedBox(height: 8),
                  _divider(cs),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(context.tr('total'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
                      const Spacer(),
                      Text(context.formatPrice(totalAmount),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                            color: cs.primary,
                            shadows: [Shadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 8)],
                          )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildQrCode(context, cs),
                  const SizedBox(height: 20),
                  _buildDownloadButton(context, cs, productName, price, shippingCost, mongikeFee,
                      totalAmount, buyerName, sellerName, buyerPhone, sellerPhone,
                      deliveryAddress, createdAt, status, productImage, paymentMethod, transactionReference),
                  const SizedBox(height: 24),
                  Text(context.tr('order_status'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 12),
                  OrderTimeline(
                    status: txStatus,
                    dispatchProof: dispatchProof,
                    courierName: d['courierName'] as String?,
                    driverPhone: d['driverPhone'] as String?,
                    receiptImageUrl: d['receiptImageUrl'] as String?,
                    trackingNumber: d['trackingNumber'] as String? ?? dispatchProof?['trackingNumber'] as String?,
                    shippingCost: shippingCost,
                    deliveryAddress: deliveryAddress,
                    orderId: orderId,
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
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.15), cs.primary.withValues(alpha: 0.05)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Icon(Icons.receipt_long, color: cs.primary, size: 36),
          ),
          const SizedBox(height: 14),
          Text(context.tr('receipt_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text('#$orderId', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text('${context.tr('placed_label')}${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
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

  Widget _buildQrCode(BuildContext context, ColorScheme cs) {
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
            QrImageView(
              data: orderId,
              version: QrVersions.auto,
              size: 120,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: cs.primary),
              dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(context.tr('scan_to_verify'),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton(
    BuildContext context,
    ColorScheme cs,
    String productName,
    double price,
    double shippingCost,
    double mongikeFee,
    double totalAmount,
    String buyerName,
    String sellerName,
    String buyerPhone,
    String sellerPhone,
    Map<String, dynamic>? deliveryAddress,
    DateTime createdAt,
    String status,
    String productImage,
    String paymentMethod,
    String? transactionReference,
  ) {
    return Center(
      child: _PdfDownloadButton(
        orderId: orderId,
        productName: productName,
        productImageUrl: productImage,
        price: price,
        shippingCost: shippingCost,
        mongikeFee: mongikeFee,
        totalAmount: totalAmount,
        buyerName: buyerName,
        sellerName: sellerName,
        buyerPhone: buyerPhone,
        sellerPhone: sellerPhone,
        deliveryAddress: deliveryAddress,
        createdAt: createdAt,
        status: status,
        paymentMethod: paymentMethod,
        transactionReference: transactionReference,
      ),
    );
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
      case 'paid_escrow_held':
      case 'escrow_hold':
        return cs.tertiary;
      case 'dispatched':
        return Colors.orange;
      case 'delivered':
      case 'delivery_confirmed':
      case 'completed':
        return cs.primary;
      case 'failed':
      case 'refunded':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'paid_escrow_held':
      case 'escrow_hold':
        return Icons.lock;
      case 'dispatched':
        return Icons.local_shipping;
      case 'delivered':
      case 'delivery_confirmed':
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.cancel;
      case 'refunded':
        return Icons.money_off;
      default:
        return Icons.hourglass_empty;
    }
  }

  String _statusLabel(String status, BuildContext context) {
    switch (status) {
      case 'awaiting_shipping_quote':
        return context.tr('awaiting_shipping_quote_label');
      case 'awaiting_payment':
        return context.tr('awaiting_payment_label');
      case 'paid_escrow_held':
      case 'escrow_hold':
        return context.tr('paid_escrow_label');
      case 'dispatched':
        return context.tr('shipped');
      case 'delivery_confirmed':
        return context.tr('confirmed');
      case 'delivered':
      case 'completed':
        return context.tr('completed');
      case 'disputed':
        return context.tr('disputed_label');
      case 'refunded':
        return context.tr('refunded');
      case 'failed':
        return context.tr('failed');
      default:
        return context.tr('pending');
    }
  }
}

class _PdfDownloadButton extends StatefulWidget {
  final String orderId;
  final String productName;
  final String productImageUrl;
  final double price;
  final double shippingCost;
  final double mongikeFee;
  final double totalAmount;
  final String buyerName;
  final String sellerName;
  final String buyerPhone;
  final String sellerPhone;
  final Map<String, dynamic>? deliveryAddress;
  final DateTime createdAt;
  final String status;
  final String paymentMethod;
  final String? transactionReference;

  const _PdfDownloadButton({
    required this.orderId,
    required this.productName,
    required this.productImageUrl,
    required this.price,
    required this.shippingCost,
    required this.mongikeFee,
    required this.totalAmount,
    required this.buyerName,
    required this.sellerName,
    required this.buyerPhone,
    required this.sellerPhone,
    this.deliveryAddress,
    required this.createdAt,
    required this.status,
    required this.paymentMethod,
    this.transactionReference,
  });

  @override
  State<_PdfDownloadButton> createState() => _PdfDownloadButtonState();
}

class _PdfDownloadButtonState extends State<_PdfDownloadButton> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isGenerating ? null : _onDownload,
        icon: _isGenerating
            ? SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
              )
            : const Icon(Icons.download_rounded, size: 18),
        label: Text(_isGenerating ? context.tr('generating_pdf') : context.tr('download_pdf_receipt')),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _onDownload() async {
    setState(() => _isGenerating = true);
    try {
      final pdfBytes = await ReceiptPdfService.generate(
        orderId: widget.orderId,
        productName: widget.productName,
        productImageUrl: widget.productImageUrl,
        price: widget.price,
        shippingCost: widget.shippingCost,
        mongikeFee: widget.mongikeFee,
        totalAmount: widget.totalAmount,
        buyerName: widget.buyerName,
        sellerName: widget.sellerName,
        buyerPhone: widget.buyerPhone,
        sellerPhone: widget.sellerPhone,
        deliveryAddress: widget.deliveryAddress,
        createdAt: widget.createdAt,
        status: widget.status,
        paymentMethod: widget.paymentMethod,
        transactionReference: widget.transactionReference,
      );
      await ReceiptPdfService.saveToDevice(pdfBytes: pdfBytes, orderId: widget.orderId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
    if (mounted) setState(() => _isGenerating = false);
  }
}
