import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

class SellerAnalyticsScreen extends StatelessWidget {
  final String sellerId;
  const SellerAnalyticsScreen({super.key, required this.sellerId});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: Padding(
        padding: const EdgeInsets.all(AppInsets.lg),
        child: Text('Seller: $sellerId', style: TextStyle(color: cs.onSurface)),
      ),
    );
  }
}
