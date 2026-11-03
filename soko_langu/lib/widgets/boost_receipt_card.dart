import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';
import '../models/boost_receipt.dart';
import '../theme/app_dimens.dart';

class BoostReceiptCard extends StatelessWidget {
  final BoostReceipt receipt;
  const BoostReceiptCard({super.key, required this.receipt});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppInsets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('boost_receipt_title'), style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: AppInsets.sm),
            Text(context.trParams('boost_receipt_product', {'product': receipt.productName}), style: TextStyle(color: cs.onSurfaceVariant)),
            Text(context.trParams('boost_receipt_amount', {'amount': '${receipt.amount}'}), style: TextStyle(color: cs.onSurfaceVariant)),
            Text(context.trParams('boost_receipt_type', {'type': receipt.boostType}), style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
