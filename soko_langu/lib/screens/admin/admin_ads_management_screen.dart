import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

class AdminAdsManagementScreen extends StatelessWidget {
  final bool embedded;
  const AdminAdsManagementScreen({super.key, this.embedded = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Ad Management')),
      body: Center(child: Text('Ad Management', style: TextStyle(color: cs.onSurface))),
    );
  }
}
