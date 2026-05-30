import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product_model.dart';
import 'google_loading.dart';
import '../extensions/context_tr.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const radius = 15.0;

    Widget card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withAlpha(25),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: product.images.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: product.images.first,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[100],
                            child: const Center(
                              child: GoogleLoading(size: 24, strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: Icon(
                              Icons.image,
                              size: 40,
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                        _buildSellerBadge(context),
                      ],
                    )
                  : Center(
                      child: Icon(
                        Icons.image,
                        size: 40,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.formatPrice(product.price),
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        product.location,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (product.rating > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.star, size: 12, color: Colors.amber[700]),
                      const SizedBox(width: 2),
                      Text(
                        "${product.rating.toStringAsFixed(1)} (${product.reviewCount})",
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(onTap: onTap, child: card);
  }

  Widget _buildSellerBadge(BuildContext context) {
    return Stack(
      children: [
        if (product.isFeaturedValid)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6F00), Color(0xFFFFA726)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, size: 10, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    context.tr('featured'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
