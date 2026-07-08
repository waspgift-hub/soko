import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

class SellerQuoteScreen extends StatelessWidget {
  const SellerQuoteScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Quote')),
      body: Center(child: Text('Seller Quote', style: TextStyle(color: cs.onSurface))),
    );
  }
}
