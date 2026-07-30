import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class RidePaymentScreen extends StatelessWidget {
  const RidePaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('payment_title'))),
      body: Center(child: Text(context.tr('coming_soon_placeholder'))),
    );
  }
}
