import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../models/product_model.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class ProductDetailV2Screen extends StatelessWidget {
  const ProductDetailV2Screen({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final image = product.images.isNotEmpty ? product.images.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Bidhaa')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(UiSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: image == null
                  ? const ColoredBox(color: UiColors.canvas)
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(color: UiColors.canvas),
                    ),
            ),
            const SizedBox(height: UiSpace.md),
            Text(product.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: UiSpace.xs),
            Text('TSh ${product.price.round()}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: UiSpace.xs),
            Text(product.sellerName, style: Theme.of(context).textTheme.bodySmall),
            if (product.location.isNotEmpty) ...[
              const SizedBox(height: UiSpace.xs),
              Text(product.location, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: UiSpace.md),
            if (product.description.isNotEmpty)
              Text(product.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: UiSpace.lg),
            UiPrimaryButton(
              label: 'Nunua sasa',
              onPressed: () => context.push(
                AppRoutes.checkoutV2,
                extra: product,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
