import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Compact marketplace card: image placeholder, badges, name, price
/// (monospace), location, seller + verification + delivery row.
class MarketProductCard extends StatefulWidget {
  final DemoProduct product;

  const MarketProductCard({super.key, required this.product});

  @override
  State<MarketProductCard> createState() => _MarketProductCardState();
}

class _MarketProductCardState extends State<MarketProductCard> {
  bool _hover = false;
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final prices = Theme.of(context).extension<SokoPrices>()!;
    final p = widget.product;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: SokoBrand.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hover ? SokoBrand.ink : SokoBrand.line,
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.05,
              child: Container(
                color: const Color(0xFFF4F5F4),
                child: Stack(
                  children: [
                    Center(
                      child: AnimatedScale(
                        scale: _hover ? 1.08 : 1.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          p.icon,
                          size: 44,
                          color: SokoBrand.muted.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Row(
                        children: [
                          if (p.boosted)
                            _Badge(
                              label: context.str('card_boosted'),
                              dark: true,
                            ),
                          if (p.boosted) const SizedBox(width: 6),
                          const _SampleChip(),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton(
                        tooltip: 'Save',
                        iconSize: 20,
                        onPressed: () =>
                            setState(() => _saved = !_saved),
                        icon: Icon(
                          _saved
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _saved
                              ? SokoBrand.error
                              : SokoBrand.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name(AppStrings.of(context).isSw),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(p.price, style: prices.amountSmall),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: SokoBrand.muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.location,
                          style: const TextStyle(
                            color: SokoBrand.muted,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.seller,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (p.verified)
                        Tooltip(
                          message: context.str('card_verified'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified,
                                size: 14,
                                color: SokoBrand.deepGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                context.str('card_verified'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: SokoBrand.deepGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 13,
                        color: SokoBrand.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.str('card_delivery'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: SokoBrand.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool dark;
  const _Badge({required this.label, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? SokoBrand.black : SokoBrand.deepGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Marks preview cards as illustrative samples (truthfulness, §41).
class _SampleChip extends StatelessWidget {
  const _SampleChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SokoBrand.line),
      ),
      child: Text(
        context.str('market_sample'),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: SokoBrand.muted,
        ),
      ),
    );
  }
}
