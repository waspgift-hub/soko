
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/flash_sale_model.dart';
import '../../models/product_model.dart';
import '../../services/deep_link_service.dart';
import '../../services/localization_service.dart';
import '../../services/product_service.dart';
import '../../services/soko_cache_manager.dart';
import '../extensions/context_tr.dart';
import 'ds/ds.dart';
import 'soko_vibe_watermark.dart';

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
    final shareAction = onShare ??
        () {
          final price =
              '${LocalizationService.supportedCurrencies[product.currency]?['symbol'] ?? 'TSh'} ${product.price.toStringAsFixed(0)}';
          final text = '${product.name}\n'
              '${context.trParams('share_price_line', {'price': price})}\n'
              '${context.tr('check_out_on')} ${DeepLinkService.productShareUrl(product.id)}';
          SharePlus.instance.share(ShareParams(text: text));
        };
    shareAction();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final imageHeight = (width * 0.88).clamp(132.0, 250.0);
        final compact = width < 170;

        return Semantics(
          button: true,
          label: [
            product.name,
            context.formatPrice(flashSale?.salePrice ?? product.price),
            if (product.rating > 0)
              '${product.rating.toStringAsFixed(1)} ${context.tr('rating')}',
          ].join(', '),
          onTap: onTap,
          child: AnimatedPress(
            onTap: onTap,
            pressedScale: 0.985,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (product.images.isNotEmpty)
                          Hero(
                            tag: 'product-img-${product.id}',
                            child: CachedNetworkImage(
                              imageUrl: getThumbnailUrl(product.images.first),
                              cacheManager: SokoCacheManager(),
                              memCacheWidth: 480,
                              memCacheHeight: 480,
                              fit: BoxFit.cover,
                              fadeInDuration:
                                  const Duration(milliseconds: 180),
                              placeholder: (_, __) => const DsSkeleton(),
                              errorWidget: (_, __, ___) => Container(
                                color: cs.surfaceContainerHigh,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: cs.onSurfaceVariant,
                                  size: 34,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: cs.surfaceContainerLow,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.image_outlined,
                              color: cs.onSurfaceVariant,
                              size: 34,
                            ),
                          ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.42),
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: () => _shareProduct(context),
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(9),
                                child: Icon(
                                  Icons.ios_share_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: IgnorePointer(
                            child: SokoVibeWatermark(),
                          ),
                        ),
                        if (product.isFeaturedValid)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: _Pill(
                              icon: Icons.verified_rounded,
                              label: context.tr('featured'),
                              background: cs.primary,
                              foreground: cs.onPrimary,
                            ),
                          ),
                        if (flashSale != null)
                          Positioned(
                            left: 8,
                            top: product.isFeaturedValid ? 41 : 8,
                            child: _Pill(
                              icon: Icons.local_offer_outlined,
                              label:
                                  '-${flashSale!.discountPercent.toStringAsFixed(0)}%',
                              background: cs.error,
                              foreground: cs.onError,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 9 : 11,
                      10,
                      compact ? 9 : 11,
                      11,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontSize: compact ? 12 : 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: flashSale != null
                                  ? DsPrice(
                                      price: flashSale!.salePrice,
                                      oldPrice: flashSale!.originalPrice,
                                      color: cs.error,
                                      size: compact ? 12.5 : 15,
                                      weight: FontWeight.w800,
                                    )
                                  : DsPrice(
                                      price: product.price,
                                      color: cs.primary,
                                      size: compact ? 12.5 : 15,
                                      weight: FontWeight.w800,
                                    ),
                            ),
                            if (product.sellerKycApproved)
                              Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (product.rating > 0) ...[
                              Icon(Icons.star_rounded,
                                  size: 14, color: cs.onSurface),
                              const SizedBox(width: 3),
                              Text(
                                product.rating.toStringAsFixed(1),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '(${product.reviewCount})',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                            if (product.condition == 'new') ...[
                              const Spacer(),
                              Text(
                                context.tr('new'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: cs.primary),
                              ),
                            ],
                          ],
                        ),
                        if (product.location.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  product.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
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
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ).copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
