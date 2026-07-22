import 'dart:typed_data';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ReceiptPdfService {
  static const _primaryColor = PdfColor.fromInt(0xFF2D6A4F);
  static const _accentColor = PdfColor.fromInt(0xFF40916C);
  static const _greyColor = PdfColor.fromInt(0xFF6B7280);
  static Future<Uint8List> generate({
    required String orderId,
    required String productName,
    required String productImageUrl,
    required double price,
    required double shippingCost,
    required double mongikeFee,
    required double totalAmount,
    required String buyerName,
    required String sellerName,
    required String buyerPhone,
    required String sellerPhone,
    required Map<String, dynamic>? deliveryAddress,
    required DateTime createdAt,
    required String status,
    required String paymentMethod,
    String? transactionReference,
  }) async {
    final pdf = pw.Document();
    final nf = NumberFormat('#,###', 'en');

    final statusLabels = {
      'paid_escrow_held': 'Secured in Escrow',
      'escrow_hold': 'Secured in Escrow',
      'dispatched': 'Dispatched',
      'delivered': 'Delivered',
      'delivery_confirmed': 'Confirmed',
      'completed': 'Completed',
      'failed': 'Failed',
      'refunded': 'Refunded',
    };

    final statusLabel = statusLabels[status] ?? (status[0].toUpperCase() + status.substring(1));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(orderId, createdAt, nf),
              pw.SizedBox(height: 16),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle('Product Details'),
              pw.SizedBox(height: 8),
              _buildInfoRow('Product', productName, nf),
              _buildInfoRow('Buyer', buyerName, nf),
              _buildInfoRow('Seller', sellerName, nf),
              if (buyerPhone.isNotEmpty) _buildInfoRow('Buyer Phone', buyerPhone, nf),
              if (sellerPhone.isNotEmpty) _buildInfoRow('Seller Phone', sellerPhone, nf),
              pw.SizedBox(height: 16),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle('Payment Breakdown'),
              pw.SizedBox(height: 8),
              _buildInfoRow('Product Price', 'TZS ${nf.format(price.toInt())}', nf),
              if (shippingCost > 0)
                _buildInfoRow('Shipping Cost', 'TZS ${nf.format(shippingCost.toInt())}', nf),
              _buildInfoRow('Processing Fee', 'TZS ${nf.format(mongikeFee.toInt())}', nf),
              pw.SizedBox(height: 8),
              pw.Container(
                height: 1,
                color: _greyColor,
              ),
              pw.SizedBox(height: 8),
              _buildTotalRow('Total Amount', 'TZS ${nf.format(totalAmount.toInt())}'),
              pw.SizedBox(height: 16),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle('Status'),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _primaryColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(statusLabel,
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 11)),
              ),
              if (deliveryAddress != null) ...[
                pw.SizedBox(height: 16),
                _buildDivider(),
                pw.SizedBox(height: 16),
                _buildSectionTitle('Delivery Address'),
                pw.SizedBox(height: 8),
                if (deliveryAddress['region'] != null)
                  _buildInfoRow('Region', deliveryAddress['region'] as String, nf),
                if (deliveryAddress['district'] != null)
                  _buildInfoRow('District', deliveryAddress['district'] as String, nf),
                if (deliveryAddress['street'] != null)
                  _buildInfoRow('Street', deliveryAddress['street'] as String, nf),
                if (deliveryAddress['landmarks'] != null)
                  _buildInfoRow('Landmarks', deliveryAddress['landmarks'] as String, nf),
              ],
              pw.SizedBox(height: 24),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle('Payment Method'),
              pw.SizedBox(height: 8),
              _buildInfoRow('Method', paymentMethod, nf),
              if (transactionReference != null && transactionReference.isNotEmpty)
                _buildInfoRow('Reference', transactionReference, nf),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Container(
                  width: 120,
                  height: 120,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: _greyColor),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: orderId,
                    width: 100,
                    height: 100,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text('Scan to verify order #$orderId',
                    style: pw.TextStyle(fontSize: 9, color: _greyColor)),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text('Soko Vibe — Thank you for your purchase!',
                    style: pw.TextStyle(fontSize: 10, color: _greyColor)),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(String orderId, DateTime createdAt, NumberFormat nf) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('SOKO VIBE', style: pw.TextStyle(
              fontSize: 22, fontWeight: pw.FontWeight.bold, color: _primaryColor,
              letterSpacing: 3,
            )),
            pw.SizedBox(height: 4),
            pw.Text('PURCHASE RECEIPT', style: pw.TextStyle(
              fontSize: 14, color: _accentColor, letterSpacing: 2,
            )),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('#$orderId', style: pw.TextStyle(
              fontSize: 12, color: _greyColor,
            )),
            pw.SizedBox(height: 2),
            pw.Text(
              '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
              style: pw.TextStyle(fontSize: 10, color: _greyColor),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildDivider() {
    return pw.Container(height: 1, color: _greyColor);
  }

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Text(title,
        style: pw.TextStyle(
            fontSize: 13, fontWeight: pw.FontWeight.bold, color: _primaryColor));
  }

  static pw.Widget _buildInfoRow(String label, String value, NumberFormat nf) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 11, color: _greyColor)),
          pw.Text(value, style: pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  static pw.Widget _buildTotalRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
      ],
    );
  }

  static Future<void> saveAndShare({
    required Uint8List pdfBytes,
    required String orderId,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt_$orderId.pdf');
    await file.writeAsBytes(pdfBytes);
    await Printing.sharePdf(bytes: pdfBytes, filename: 'receipt_$orderId.pdf');
  }

  static Future<void> saveToDevice({
    required Uint8List pdfBytes,
    required String orderId,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt_$orderId.pdf');
    await file.writeAsBytes(pdfBytes);
    await Printing.sharePdf(bytes: pdfBytes, filename: 'receipt_$orderId.pdf');
  }
}
