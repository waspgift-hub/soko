import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/routes.dart';
import '../extensions/context_tr.dart';
import '../theme/design_tokens.dart';
import '../theme/responsive_typography.dart';
import 'banners/soko_banner_theme.dart';

/// Seller-facing internal promo for Boost (NOT AdMob).
class AdsPromoBanner extends StatelessWidget {
  const AdsPromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return ResponsiveBanner(
      minHeight: SokoBannerTheme.minHeight,
      margin: EdgeInsets.zero,
      borderRadius: SokoBannerTheme.borderRadius,
      onTap: () => context.push(AppRoutes.boostProduct),
      decoration: SokoBannerTheme.surfaceDecoration(
        context,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
            cs.surfaceContainerLow,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SokoBannerTheme.badge(
                    context,
                    context.tr('boost_promo_title'),
                    icon: Icons.rocket_launch_outlined,
                  ),
                  const SizedBox(height: 12),
                  BannerText(
                    context.tr('boost_promo_subtitle'),
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.45,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  BannerText(
                    context.tr('boost_promo_desc'),
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  SokoBannerTheme.ctaPill(context, context.tr('boost_promo_cta')),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Container(
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.10)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.trending_up_rounded, size: 40, color: cs.primary),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('boost_product'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Ds.labelLg(
                        cs.primary,
                      ).copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
