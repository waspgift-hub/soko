import 'dart:convert';
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
    required double clickpesaFee,
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
    double platformFee = 0,
    double sellerReceives = 0,
    String sellerLocation = '',
    String productDescription = '',
    String productDetails = '',
    String lang = 'sw',
  }) async {
    final pdf = pw.Document();
    final nf = NumberFormat('#,###', 'en');
    final isSw = lang == 'sw';

    String t(String sw, String en) => isSw ? sw : en;

    final statusLabels = {
      'paid_escrow_held': t('Imehifadhiwa Escrow', 'Secured in Escrow'),
      'escrow_hold': t('Imehifadhiwa Escrow', 'Secured in Escrow'),
      'dispatched': t('Imesafirishwa', 'Dispatched'),
      'delivered': t('Imefikishwa', 'Delivered'),
      'delivery_confirmed': t('Imethibitishwa', 'Confirmed'),
      'completed': t('Imekamilika', 'Completed'),
      'failed': t('Imeshindwa', 'Failed'),
      'refunded': t('Imerejeshwa', 'Refunded'),
    };
    final statusLabel = statusLabels[status] ?? status;

    final qrData = jsonEncode({
      'type': 'soko_vibe_receipt',
      'orderId': orderId,
      'date': createdAt.toIso8601String(),
      'product': {
        'name': productName,
        'description': productDescription,
        'details': productDetails,
        'price': price,
      },
      'seller': {'name': sellerName, 'phone': sellerPhone, 'location': sellerLocation},
      'buyer': {'name': buyerName, 'phone': buyerPhone},
      'payment': {
        'total': totalAmount, 'productPrice': price, 'shippingCost': shippingCost,
        'commission': platformFee, 'processingFee': clickpesaFee, 'sellerReceives': sellerReceives,
        'method': paymentMethod, 'reference': transactionReference,
      },
      'status': status,
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader(orderId, createdAt, nf, isSw),
              pw.SizedBox(height: 16),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle(t('Maelezo ya Bidhaa', 'Product Details')),
              pw.SizedBox(height: 8),
              _buildInfoRow(t('Bidhaa', 'Product'), productName, nf),
              if (productDescription.isNotEmpty)
                _buildInfoRow(t('Maelezo', 'Description'), productDescription, nf),
              if (productDetails.isNotEmpty)
                _buildInfoRow(t('Kinachouzwa', 'Details'), productDetails, nf),
              _buildInfoRow(t('Mnunuzi', 'Buyer'), buyerName, nf),
              _buildInfoRow(t('Muuzaji', 'Seller'), sellerName, nf),
              if (buyerPhone.isNotEmpty)
                _buildInfoRow(t('Simu ya Mnunuzi', 'Buyer Phone'), buyerPhone, nf),
              if (sellerPhone.isNotEmpty)
                _buildInfoRow(t('Simu ya Muuzaji', 'Seller Phone'), sellerPhone, nf),
              if (sellerLocation.isNotEmpty)
                _buildInfoRow(t('Duka lipo', 'Shop Location'), sellerLocation, nf),
              pw.SizedBox(height: 16),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle(t('Mgawanyo wa Malipo', 'Payment Breakdown')),
              pw.SizedBox(height: 8),
              _buildInfoRow(t('Bei ya Bidhaa', 'Product Price'), 'TZS ${nf.format(price.toInt())}', nf),
              if (shippingCost > 0)
                _buildInfoRow(t('Nauli ya Usafirishaji', 'Shipping Cost'), 'TZS ${nf.format(shippingCost.toInt())}', nf),
              if (platformFee > 0)
                _buildInfoRow(t('Commission ya Soko Vibe', 'Soko Vibe Commission'), 'TZS ${nf.format(platformFee.toInt())}', nf),
              _buildInfoRow(t('Ada ya Kuchakata', 'Processing Fee'), 'TZS ${nf.format(clickpesaFee.toInt())}', nf),
              pw.SizedBox(height: 8),
              pw.Container(height: 1, color: _greyColor),
              pw.SizedBox(height: 8),
              _buildTotalRow(t('Jumla', 'Total Amount'), 'TZS ${nf.format(totalAmount.toInt())}'),
              if (sellerReceives > 0) ...[
                pw.SizedBox(height: 2),
                _buildInfoRow(t('Muuzaji anapata', 'Seller Receives'), 'TZS ${nf.format(sellerReceives.toInt())}', nf),
              ],
              pw.SizedBox(height: 16),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle(t('Hali', 'Status')),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _primaryColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(statusLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 11)),
              ),
              if (deliveryAddress != null) ...[
                pw.SizedBox(height: 16),
                _buildDivider(),
                pw.SizedBox(height: 16),
                _buildSectionTitle(t('Anwani ya Usafirishaji', 'Delivery Address')),
                pw.SizedBox(height: 8),
                if (deliveryAddress['region'] != null)
                  _buildInfoRow(t('Mkoa', 'Region'), deliveryAddress['region'] as String, nf),
                if (deliveryAddress['district'] != null)
                  _buildInfoRow(t('Wilaya', 'District'), deliveryAddress['district'] as String, nf),
                if (deliveryAddress['ward'] != null && (deliveryAddress['ward'] as String? ?? '').isNotEmpty)
                  _buildInfoRow(t('Kata', 'Ward'), deliveryAddress['ward'] as String, nf),
                if (deliveryAddress['street'] != null)
                  _buildInfoRow(t('Mtaa', 'Street'), deliveryAddress['street'] as String, nf),
                if (deliveryAddress['landmarks'] != null)
                  _buildInfoRow(t('Alama', 'Landmarks'), deliveryAddress['landmarks'] as String, nf),
              ],
              pw.SizedBox(height: 24),
              _buildDivider(),
              pw.SizedBox(height: 16),
              _buildSectionTitle(t('Njia ya Malipo', 'Payment Method')),
              pw.SizedBox(height: 8),
              _buildInfoRow(t('Njia', 'Method'), paymentMethod, nf),
              if (transactionReference != null && transactionReference.isNotEmpty)
                _buildInfoRow(t('Rejea', 'Reference'), transactionReference, nf),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Container(
                  width: 140,
                  height: 140,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: _greyColor),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrData,
                    width: 120,
                    height: 120,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  t('Scan QR kupata taarifa zote', 'Scan QR for full details'),
                  style: pw.TextStyle(fontSize: 9, color: _greyColor)),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  t('Soko Vibe — Asante kwa ununuzi wako!', 'Soko Vibe — Thank you for your purchase!'),
                  style: pw.TextStyle(fontSize: 10, color: _greyColor)),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(String orderId, DateTime createdAt, NumberFormat nf, bool isSw) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('SOKO VIBE', style: pw.TextStyle(
              fontSize: 22, fontWeight: pw.FontWeight.bold, color: _primaryColor, letterSpacing: 3)),
            pw.SizedBox(height: 4),
            pw.Text(isSw ? 'RISITI YA UNUNUZI' : 'PURCHASE RECEIPT', style: pw.TextStyle(
              fontSize: 14, color: _accentColor, letterSpacing: 2)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('#$orderId', style: pw.TextStyle(fontSize: 12, color: _greyColor)),
            pw.SizedBox(height: 2),
            pw.Text(
              '${createdAt.day}/${createdAt.month}/${createdAt.year} '
              '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
              style: pw.TextStyle(fontSize: 10, color: _greyColor)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildDivider() => pw.Container(height: 1, color: _greyColor);

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _primaryColor));
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
        pw.Text(label, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
        pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
      ],
    );
  }

  static Future<void> saveAndShare({
    required Uint8List pdfBytes, required String orderId,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt_$orderId.pdf');
    await file.writeAsBytes(pdfBytes);
    await Printing.sharePdf(bytes: pdfBytes, filename: 'receipt_$orderId.pdf');
  }

  static Future<void> saveToDevice({
    required Uint8List pdfBytes, required String orderId,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt_$orderId.pdf');
    await file.writeAsBytes(pdfBytes);
    await Printing.sharePdf(bytes: pdfBytes, filename: 'receipt_$orderId.pdf');
  }
}
