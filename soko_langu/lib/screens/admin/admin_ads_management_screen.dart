import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_dimens.dart';

class AdminAdsManagementScreen extends StatelessWidget {
  final bool embedded;
  const AdminAdsManagementScreen({super.key, this.embedded = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: embedded ? null : AppBar(title: Text(context.tr('ad_management'))),
      body: Center(child: Text(context.tr('ad_management'), style: TextStyle(color: cs.onSurface))),
    );
  }
}
