import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class AdminTransactionsTab extends StatelessWidget {
  const AdminTransactionsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Text(context.tr('transactions'), style: TextStyle(color: cs.onSurface)));
  }
}
