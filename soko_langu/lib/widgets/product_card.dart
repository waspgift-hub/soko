import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../services/deep_link_service.dart';
import '../../services/localization_service.dart';
import '../../services/soko_cache_manager.dart';
import '../extensions/context_tr.dart';
import '../theme/app_colors.dart';
import '../theme/marketplace_design_tokens.dart';
import 'soko_vibe_watermark.dart';
import 'ds/ds.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final FlashSale? flashSale;
  final VoidCallback? onShare;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.flashSale,
    this.onShare,
  });

  void _shareProduct(BuildContext context) {
    final shareAction = onShare ?? () {
      final price =
          '${LocalizationService.supportedCurrencies[product.currency]?['symbol'] ?? 'TSh'} ${product.price.toStringAsFixed(0)}';
      final text =
          '${product.name}\n'
          '${context.trParams('share_price_line', {'price': price})}\n'
          '${context.tr('check_out_on')} ${DeepLinkService.productShareUrl(product.id)}';
      SharePlus.instance.share(ShareParams(text: text));
    };
    shareAction();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayPrice = flashSale?.salePrice ?? product.price;
    final semanticsLabel = [
      product.name,
      context.formatPrice(displayPrice),
      if (product.rating > 0)
        '${product.rating.toStringAsFixed(1)} ${context.tr('rating')}',
      if (product.location.trim().isNotEmpty) product.location,
    ].join(', ');

    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      child: AnimatedPress(
        onTap: onTap,
        pressedScale: 0.985,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final titleSize = width < 150 ? 13.0 : 14.0;
            final priceSize = width < 150 ? 13.0 : 14.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductImage(
                  product: product,
                  flashSale: flashSale,
                  onShare: () => _shareProduct(context),
                ),
                const SizedBox(height: 9),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MarketplaceTokens.productTitle(context).copyWith(
                    fontSize: titleSize,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                if (flashSale != null)
                  DsPrice(
                    price: flashSale!.salePrice,
                    oldPrice: flashSale!.originalPrice,
                    color: cs.error,
                    size: priceSize,
                    weight: FontWeight.w700,
                  )
                else
                  DsPrice(
                    price: product.price,
                    color: cs.onSurface,
                    size: priceSize,
                    weight: FontWeight.w700,
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MarketplaceTokens.metadata(context),
                      ),
                    ),
                    if (product.sellerKycApproved) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: cs.successGreen,
                        semanticLabel: context.tr('verified'),
                      ),
                    ],
                  ],
                ),
                if (product.rating > 0) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        '${product.rating.toStringAsFixed(1)} (${product.reviewCount})',
                        style: MarketplaceTokens.metadata(context),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final Product product;
  final FlashSale? flashSale;
  final VoidCallback onShare;

  const _ProductImage({
    required this.product,
    required this.flashSale,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MarketplaceTokens.imageRadius),
        child: product.images.isEmpty
            ? ColoredBox(
                color: cs.surfaceContainerLow,
                child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 34),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product-img-${product.id}',
                    child: CachedNetworkImage(
                      imageUrl: getThumbnailUrl(product.images.first),
                      cacheManager: SokoCacheManager(),
                      memCacheWidth: 480,
                      memCacheHeight: 480,
                      fit: BoxFit.cover,
                      fadeInDuration: MarketplaceTokens.standardMotion,
                      placeholder: (_, __) => ColoredBox(
                        color: cs.surfaceContainerLow,
                        child: const DsSkeleton(),
                      ),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: cs.surfaceContainerLow,
                        child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant, size: 32),
                      ),
                    ),
                  ),
                  if (product.isFeaturedValid)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _ImageLabel(
                        label: context.tr('featured'),
                        background: Colors.black.withValues(alpha: 0.72),
                        foreground: Colors.white,
                      ),
                    ),
                  if (flashSale != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _ImageLabel(
                        label: '-${flashSale!.discountPercent.toStringAsFixed(0)}%',
                        background: cs.error,
                        foreground: cs.onError,
                      ),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.52),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onShare,
                        child: const SizedBox(
                          width: MarketplaceTokens.touchTarget,
                          height: MarketplaceTokens.touchTarget,
                          child: Icon(Icons.share_outlined, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: IgnorePointer(child: SokoVibeWatermark()),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ImageLabel extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _ImageLabel({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
