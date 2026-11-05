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
    final cs = Theme.of(context).colorScheme;
    final manager = context.watch<AdManager>();

    if (!manager.config.isPlacementEnabled(placement)) {
      return const SizedBox.shrink();
    }
    if (!manager.adsEnabledForUser || kIsWeb) {
      return const SizedBox.shrink();
    }

    // Only claim screen real estate when there is an actual creative to show.
    // The previous version reserved 50px unconditionally, leaving a blank
    // banner-shaped gap in title bars and footers whenever no fill arrived.
    final creative = manager.bannerWidgetFor(
      placement,
      slotKey: placement.id,
    );
    if (creative == null) {
      return const SizedBox.shrink();
    }

    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
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

/// Renders the creative for a placement. The caller is responsible for
/// checking that a creative exists before mounting this widget; this class
/// exists so the old `_BannerReserve` skeleton could be removed without
/// touching every call site.
class _BannerHost extends StatelessWidget {
  const _BannerHost({required this.placement});

  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<AdManager>();
    return manager.bannerWidgetFor(
      placement,
      slotKey: placement.id,
    ) ?? const SizedBox.shrink();
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
            style: Ds.labelSm(cs.contentMuted).copyWith(
              fontSize: 10,
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
