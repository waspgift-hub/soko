import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_breakpoints.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/product_card.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// Compact product discovery grid (2→5 columns by layout).
class MarketplaceSection extends StatelessWidget {
  const MarketplaceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final layout =
        layoutOf(MediaQuery.sizeOf(context).width);
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedReveal(
            child: SectionHeader(
              eyebrow: context.str('market_eyebrow'),
              title: context.str('market_title'),
              sub: context.str('market_sub'),
            ),
          ),
          const SizedBox(height: 40),
          LayoutBuilder(
            builder: (context, c) {
              // Card height follows the column width: square-ish image plus
              // a fixed details budget, so no layout overflows at any width.
              const gap = 18.0;
              final cols = layout.marketColumns;
              final colW = (c.maxWidth - gap * (cols - 1)) / cols;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: colW / 1.05 + 195,
                ),
                itemCount: demoProducts.length,
                itemBuilder: (_, i) => AnimatedReveal(
                  delay: Duration(milliseconds: (i % 4) * 80),
                  child: MarketProductCard(product: demoProducts[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
