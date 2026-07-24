import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';

class BoostReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const BoostReceiptScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nf = NumberFormat('#,###', 'en');
    final tier = data['tier'] as String? ?? '';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? amount;
    final productName = data['productName'] as String? ?? '';
    final durationDays = data['durationDays'] as int? ?? 0;
    final createdAt = data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : '';
    final startDate = createdAt is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : '';
    final expiryDate = createdAt is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm')
            .format(createdAt.toDate().add(Duration(days: durationDays)))
        : '';
    final orderId = data['transactionId'] as String? ?? '';
    final tierColors = <String, Color>{
      'bronze': Color(0xFFCD7F32),
      'silver': Color(0xFFC0C0C0),
      'gold': Color(0xFFFFD700),
    };
    final tierColor = tierColors[tier.toLowerCase()] ?? cs.primary;

    final qrData = jsonEncode({
      'type': 'boost',
      'id': orderId,
      'product': productName,
      'tier': tier,
      'amount': totalAmount,
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('boost_receipt')),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Icon(Icons.rocket_launch_rounded, size: 40, color: tierColor),
                const SizedBox(height: 8),
                Text(
                  context.tr('boost_product'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (tier.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tier.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tierColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                _row(cs, context.tr('product'), productName),
                _row(cs, context.tr('boost_tier'), tier),
                _row(cs, context.tr('duration'), '${durationDays} ${context.tr('days')}'),
                _row(cs, context.tr('start_date'), startDate),
                _row(cs, context.tr('end_date'), expiryDate),
                const Divider(height: 24),
                _row(cs, context.tr('receipt_total'), 'TZS ${nf(totalAmount.toInt())}',
                    valueBold: true, valueColor: cs.primary),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 140,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: cs.primary,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    ColorScheme cs,
    String label,
    String value, {
    bool valueBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}