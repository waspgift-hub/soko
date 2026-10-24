import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/routes.dart';
import '../extensions/context_tr.dart';
import '../theme/design_tokens.dart';
import '../theme/responsive_typography.dart';

/// Seller-facing promo for Boost: buy a boost package and your listing jumps
/// to the top of discovery/search for a fixed number of days.
class AdsPromoBanner extends StatelessWidget {
  const AdsPromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push(AppRoutes.boostProduct),
      child: ResponsiveBanner(
        minHeight: 180,
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        borderRadius: BorderRadius.circular(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.18),
              cs.primary.withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.tr('boost_promo_title'),
                        style: Ds.bannerCta(cs.primary).copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    BannerText(
                      context.tr('boost_promo_subtitle'),
                      style: Ds.bannerTitle(cs.onSurface).copyWith(height: 1.2),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 6),
                    BannerText(
                      context.tr('boost_promo_desc'),
                      style: Ds.bannerSubtitle(cs.onSurfaceVariant),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        context.tr('boost_promo_cta'),
                        style: Ds.bannerCta(cs.onPrimary).copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.rocket_launch_rounded,
                        size: 48,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('boost_product'),
                        style: Ds.labelLarge(cs.primary).copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}