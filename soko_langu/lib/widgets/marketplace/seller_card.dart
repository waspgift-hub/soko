import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Compact seller tile for horizontal rails.
///
/// Circle avatar with storefront badge, name, rating and optional verification.
/// Intrinsic width (typically 100–120dp) for horizontal scrolling lists.
class SellerCard extends StatelessWidget {
  final String name;
  final String imageUrl;
  final double rating;
  final int reviewCount;
  final bool kycVerified;
  final VoidCallback onTap;
  final Widget? trailing;

  const SellerCard({
    super.key,
    required this.name,
    required this.imageUrl,
    this.rating = 0,
    this.reviewCount = 0,
    this.kycVerified = false,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 110,
      child: Semantics(
        button: true,
        label: name,
        child: AnimatedPress(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: cs.surfaceContainerHighest,
                    backgroundImage: imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
                    child: imageUrl.isEmpty
                        ? Icon(Icons.storefront, size: 28, color: cs.onSurfaceVariant)
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                      child: const Icon(Icons.storefront, size: 11, color: Colors.white),                    ),
                  ),
                  if (kycVerified)
                    Positioned(
                      left: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                        child: Icon(Icons.verified, size: 16, color: cs.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              const SizedBox(height: 2),
              if (rating > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 12, color: cs.primary),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    if (reviewCount > 0) ...[
                      const SizedBox(width: 3),
                      Text('($reviewCount)', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              if (trailing != null) ...[
                const SizedBox(height: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}