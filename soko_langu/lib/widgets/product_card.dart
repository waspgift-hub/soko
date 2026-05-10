import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../main.dart';
import '../widgets/tilt_card.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.of(context);
    final isSilver = config.accountTier == 'silver';
    final isPremium = config.accountTier == 'premium';
    final radius = isSilver ? 20.0 : (isPremium ? 18.0 : 15.0);

    Widget card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: isSilver
                ? Colors.blueGrey.withAlpha(40)
                : isPremium
                ? Colors.amber.withAlpha(25)
                : Colors.green.withAlpha(25),
            blurRadius: isSilver ? 20 : 15,
            offset: const Offset(0, 5),
            spreadRadius: isSilver ? 2 : 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: Container(
                decoration: BoxDecoration(
                  image: product.images.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(product.images.first),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: product.images.isEmpty ? Colors.grey[200] : null,
                ),
                child: product.images.isEmpty
                    ? Center(
                        child: Icon(
                          Icons.image,
                          size: 40,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      )
                    : _buildSellerBadge(),
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
                  "${product.currency ?? 'Tsh'} ${product.price.toStringAsFixed(0)}",
                  style: TextStyle(
                    color: isSilver
                        ? Colors.blueGrey
                        : (isPremium ? Colors.amber[800] : Colors.green),
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
                    if (product.sellerTier == 'silver' ||
                        product.sellerTier == 'premium')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: product.sellerTier == 'silver'
                              ? Colors.blueGrey.withAlpha(30)
                              : Colors.amber.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          product.sellerTier == 'silver' ? 'S' : 'P',
                          style: TextStyle(
                            fontSize: 9,
                            color: product.sellerTier == 'silver'
                                ? Colors.blueGrey[700]
                                : Colors.amber[800],
                            fontWeight: FontWeight.bold,
                          ),
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

    if (isSilver) {
      return TiltCard(tiltFactor: 0.03, onTap: onTap, child: card);
    }

    return GestureDetector(onTap: onTap, child: card);
  }

  Widget _buildSellerBadge() {
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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, size: 10, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'Featured',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (product.sellerTier == 'silver')
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withAlpha(200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Silver',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (product.sellerTier == 'premium')
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Premium',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
