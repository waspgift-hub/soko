import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';
import '../../services/ads/ad_config.dart';
import '../../services/ads/ad_manager.dart';

/// How an inline ad sits inside a screen.
enum AdSlotVariant {
  /// Pinned above the bottom navigation / safe area. Used on list screens where
  /// content scrolls beneath a persistent footer. Never used where it would
  /// collide with a primary action.
  pinnedFooter,

  /// Inline block inside a scroll view. Reserves its height so the feed does not
  /// reflow when the creative arrives.
  feedGap,

  /// Inline block above the fold of a scroll view that has no other ad.
  inline,
}

/// Responsive metrics for the banner slot.
class AdSlotSizing {
  AdSlotSizing._();

  static const double bannerHeight = 50;
  static const double labelBarHeight = 16;
  static const double totalHeight = bannerHeight + labelBarHeight;

  /// Constrains the ad to the app's content width so it does not stretch across
  /// a tablet or desktop window.
  static double maxWidthFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > Ds.maxContentWidth ? Ds.maxContentWidth : width;
  }
}

/// A single reusable mount point for inline AdMob placements.
///
/// Screens never load an ad themselves. They declare *where* an ad belongs by
/// passing an [AdPlacement]; the [AdManager] decides whether anything renders,
/// loads it, caches it, applies frequency rules, honours the Blue Tick
/// exemption and disposes it.
///
/// Rendering contract:
/// * Renders nothing at all when ineligible, so a Blue Tick seller sees a clean
///   screen with no gap.
/// * Reserves its own height while loading so the feed does not jump.
/// * Always carries a visible "AD" disclosure above the creative.
class AdSlot extends StatelessWidget {
  const AdSlot({
    super.key,
    required this.placement,
    this.variant = AdSlotVariant.feedGap,
    this.topMargin,
    this.bottomMargin,
    this.showLabel = true,
  });

  final AdPlacement placement;
  final AdSlotVariant variant;
  final double? topMargin;
  final double? bottomMargin;

  /// Disables the visible disclosure strip. Only appropriate for an AdMob
  /// format that renders its own "AdChoices"/"Sponsored" disclosure.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<AdManager>();

    if (!manager.config.isPlacementEnabled(placement)) {
      return const SizedBox.shrink();
    }
    if (!manager.adsEnabledForUser || kIsWeb) {
      return const SizedBox.shrink();
    }

    final body = Center(
      child: SizedBox(
        width: AdSlotSizing.maxWidthFor(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLabel) const _AdDisclosure(),
            SizedBox(
              height: AdSlotSizing.bannerHeight,
              child: _BannerHost(placement: placement),
            ),
          ],
        ),
      ),
    );

    return switch (variant) {
      AdSlotVariant.pinnedFooter => _PinnedFooter(
          top: topMargin,
          bottom: bottomMargin,
          child: body,
        ),
      AdSlotVariant.feedGap => Padding(
          padding: EdgeInsets.only(
            top: topMargin ?? Ds.sp4,
            bottom: bottomMargin ?? Ds.sp4,
          ),
          child: body,
        ),
      AdSlotVariant.inline => Padding(
          padding: EdgeInsets.only(
            top: topMargin ?? Ds.sp3,
            bottom: bottomMargin ?? Ds.sp3,
          ),
          child: body,
        ),
    };
  }
}

/// Reserves the exact banner height and swaps in the creative once loaded, so
/// the surrounding layout never reflows on fill.
class _BannerHost extends StatelessWidget {
  const _BannerHost({required this.placement});

  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<AdManager>();
    final creative = manager.bannerWidgetFor(
      placement,
      slotKey: placement.id,
    );
    if (creative == null) return const _BannerReserve();
    return creative;
  }
}

/// Neutral skeleton shown while the creative loads.
///
/// Deliberately unlabelled and non-interactive. The old implementation rendered
/// a fake green "Sponsored / View" card on web and on every no-fill failure,
/// which misrepresented first-party content as advertising and covered real
/// content for nothing.
class _BannerReserve extends StatelessWidget {
  const _BannerReserve();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Ds.rSm),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// "AD" disclosure strip. Small, uppercase, muted — present but not loud, and
/// never visually dominant over marketplace content.
class _AdDisclosure extends StatelessWidget {
  const _AdDisclosure();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: AdSlotSizing.labelBarHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'AD',
            style: AppTypography.monoLabel(cs.contentMuted).copyWith(
              fontSize: AppFontSize.xs,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned footer with correct safe-area handling.
///
/// `Scaffold.bottomNavigationBar` does not apply the bottom inset on its own, so
/// the previous banner sat flush against the iOS home indicator and the Android
/// gesture bar at six of its ten call sites.
class _PinnedFooter extends StatelessWidget {
  const _PinnedFooter({
    required this.child,
    this.top,
    this.bottom,
  });

  final Widget child;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.hairline)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: top ?? Ds.sp2,
          bottom: bottom ?? Ds.sp2 + bottomInset,
          left: Ds.sp3,
          right: Ds.sp3,
        ),
        child: child,
      ),
    );
  }
}

/// Fires a placement-controlled interstitial at a deliberate transition point.
///
/// Screens call [showInterstitial] / [showRewarded] from a navigation or submit
/// callback and never inspect frequency caps, the Blue Tick exemption or critical
/// flows themselves.
class AdTransitions {
  AdTransitions._();

  static Future<bool> showInterstitial(
    BuildContext context,
    AdPlacement placement,
  ) =>
      adManagerOf(context).showInterstitial(placement);

  static Future<bool> showRewarded(
    BuildContext context,
    AdPlacement placement, {
    required VoidCallback onUserEarned,
  }) =>
      adManagerOf(context).showRewarded(
        placement,
        onUserEarned: onUserEarned,
      );
}
