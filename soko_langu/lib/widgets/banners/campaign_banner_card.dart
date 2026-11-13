import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../models/banner_model.dart';
import '../../services/banner_service.dart';
import '../../theme/responsive_typography.dart';
import '../product_cached_image.dart';
import 'soko_banner_theme.dart';

/// Renders an admin-configured [BannerCampaign] (NOT AdMob).
/// Reusable across placements; caller controls eligibility/data source.
class CampaignBannerCard extends StatelessWidget {
  const CampaignBannerCard({
    super.key,
    required this.campaign,
    this.bannerService,
    this.onTap,
    this.onImpressionRecorded,
  });

  final BannerCampaign campaign;
  final BannerService? bannerService;
  final VoidCallback? onTap;

  /// When provided (e.g. by [CampaignBannerSlot]), slot owns impression/click tracking.
  final VoidCallback? onImpressionRecorded;

  String _typeLabel(BannerType type) => switch (type) {
    BannerType.sponsoredAd => 'Sponsored',
    BannerType.promotion => 'Promotion',
    BannerType.newFeature => 'New feature',
    BannerType.platformAnnouncement => 'Announcement',
    BannerType.adminConfigured => 'Soko Vibe',
  };

  IconData _typeIcon(BannerType type) => switch (type) {
    BannerType.sponsoredAd => Icons.campaign_outlined,
    BannerType.promotion => Icons.local_offer_outlined,
    BannerType.newFeature => Icons.auto_awesome_outlined,
    BannerType.platformAnnouncement => Icons.info_outline_rounded,
    BannerType.adminConfigured => Icons.storefront_outlined,
  };

  void _handleTap(BuildContext context) {
    if (onImpressionRecorded != null) {
      onTap?.call();
      return;
    }
    bannerService?.recordClick(bannerId: campaign.id, placement: campaign.placement);
    if (onTap != null) {
      onTap!();
      return;
    }
    final v = campaign.destinationValue.trim();
    switch (campaign.destinationType) {
      case BannerDestinationType.productDetail:
        if (v.isNotEmpty) context.push('${AppRoutes.productDetail}/$v');
      case BannerDestinationType.categoryPage:
        if (v.isNotEmpty) context.push('/category/$v');
      case BannerDestinationType.sellerProfile:
        if (v.isNotEmpty) context.push('${AppRoutes.publicProfile}/$v');
      case BannerDestinationType.flashSalePage:
        context.push(AppRoutes.flashSale);
      case BannerDestinationType.addProduct:
        context.push(AppRoutes.addProduct);
      case BannerDestinationType.boostProduct:
        context.push(AppRoutes.boostProduct);
      case BannerDestinationType.kycPage:
        context.push(AppRoutes.kyc);
      case BannerDestinationType.notificationsPage:
        context.push(AppRoutes.notifications);
      case BannerDestinationType.externalUrl:
      case BannerDestinationType.deepLink:
        if (v.isNotEmpty) {
          // Safe fallback: show destination in-app context only when route-like;
          // full external launching is handled by existing app URL handlers where present.
          if (v.startsWith('/')) context.push(v);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (onImpressionRecorded == null) {
      bannerService?.recordImpression(bannerId: campaign.id, placement: campaign.placement);
    } else {
      onImpressionRecorded!.call();
    }
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final hasImage = (campaign.imageUrl ?? '').trim().isNotEmpty;
    final isSponsored = campaign.type == BannerType.sponsoredAd;

    return SokoBannerFrame(
      child: Semantics(
        button: true,
        label: '${_typeLabel(campaign.type)}: ${campaign.title}. ${campaign.mainText}',
        child: ResponsiveBanner(
          minHeight: SokoBannerTheme.minHeight,
          margin: EdgeInsets.zero,
          borderRadius: SokoBannerTheme.borderRadius,
          decoration: SokoBannerTheme.surfaceDecoration(context),
          onTap: () => _handleTap(context),
          child: ClipRRect(
            borderRadius: SokoBannerTheme.borderRadius,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SokoBannerTheme.badge(
                              context,
                              _typeLabel(campaign.type),
                              icon: _typeIcon(campaign.type),
                            ),
                            if (isSponsored && (campaign.sponsorName ?? '').trim().isNotEmpty)
                              SokoBannerTheme.badge(
                                context,
                                campaign.sponsorName!.trim(),
                                icon: Icons.verified_outlined,
                                background: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                                foreground: cs.onSurfaceVariant,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        BannerText(
                          campaign.title.isNotEmpty ? campaign.title : campaign.mainText,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                        ),
                        if (campaign.subtitle?.trim().isNotEmpty == true ||
                            campaign.mainText.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          BannerText(
                            (campaign.subtitle?.trim().isNotEmpty == true
                                    ? campaign.subtitle!
                                    : campaign.mainText)
                                .trim(),
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (campaign.ctaLabel.trim().isNotEmpty)
                          SokoBannerTheme.ctaPill(context, campaign.ctaLabel.trim()),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 9,
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasImage
                        ? ProductCachedImage(url: campaign.imageUrl!, fit: BoxFit.cover)
                        : _VisualFallback(
                            icon: _typeIcon(campaign.type),
                            reduceMotion: reduceMotion,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VisualFallback extends StatelessWidget {
  const _VisualFallback({required this.icon, required this.reduceMotion});
  final IconData icon;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.14),
            cs.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: cs.primary),
        ),
      ),
    );
  }
}
