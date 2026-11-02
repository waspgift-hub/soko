import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class SellerDashboardV2Screen extends StatelessWidget {
  const SellerDashboardV2Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashibodi ya muuzaji')),
      body: ListView(
        padding: const EdgeInsets.all(UiSpace.md),
        children: [
          Text('Bidhaa na maagizo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: UiSpace.md),
          UiPrimaryButton(
            label: 'Ongeza bidhaa',
            onPressed: () => context.push(AppRoutes.addProduct),
          ),
          const SizedBox(height: UiSpace.sm),
          UiTextAction(
            label: 'Bidhaa zangu',
            onPressed: () => context.push(AppRoutes.myAds),
          ),
          UiTextAction(
            label: 'Maagizo ya wateja',
            onPressed: () => context.push(AppRoutes.sellerOrders),
          ),
          UiTextAction(
            label: 'Mapato',
            onPressed: () => context.push(AppRoutes.sellerEarnings),
          ),
          UiTextAction(
            label: 'Takwimu',
            onPressed: () => context.push(AppRoutes.sellerAnalytics),
          ),
        ],
      ),
    );
  }
}
