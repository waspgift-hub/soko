import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

class ReceiptScreen extends StatelessWidget {
  final String orderId;
  const ReceiptScreen({super.key, required this.orderId});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: Padding(
        padding: const EdgeInsets.all(AppInsets.lg),
        child: Text('Order: $orderId', style: TextStyle(color: cs.onSurface)),
      ),
    );
  }
}
