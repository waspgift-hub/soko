import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

class AdminTransactionsTab extends StatelessWidget {
  const AdminTransactionsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Text('Transactions', style: TextStyle(color: cs.onSurface)));
  }
}
