import 'package:flutter/material.dart';

import '../ds/ds_empty_state.dart';
import 'soko_animated_art.dart';
import 'soko_marketplace_art.dart';

/// Semantic illustration kinds used across Soko Vibe.
enum SokoIllustration {
  emptyCart,
  emptyWishlist,
  emptyOrders,
  emptyChat,
  emptySearch,
  emptyCategory,
  emptyProducts,
  emptyMusic,
  emptyLocation,
  emptyNotifications,
  emptyTransactions,
  emptyShipping,
  noInternet,
  upload,
  download,
  paymentPending,
  paymentProcessing,
  paymentSuccess,
  orderConfirmed,
  sellerDashboard,
  productCreated,
  kycPending,
  kycVerified,
  recentlyViewed,
  splash,
  onboarding,
  homePromo,
  productLoading,
  errorRetry,
}

/// Reusable animated illustration entry point.
///
/// Wraps the hand-drawn [CustomPainter] widgets so screens never manage
/// [AnimationController]s directly. Reduced-motion preferences disable ticking;
/// the illustration then renders its first frame.
class SokoAnimatedIllustration extends StatelessWidget {
  const SokoAnimatedIllustration(
    this.illustration, {
    super.key,
    this.size = 96,
    this.color,
    this.animate = true,
  });

  final SokoIllustration illustration;
  final double size;
  final Color? color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldTick = animate && !reducedMotion;

    final art = _buildArt(illustration, size, color);

    // TickerMode is the Flutter-native way to pause every descendant ticker
    // (including the controllers owned by the art widgets) without disposing
    // them, so a reduced-motion or off-screen illustration stays cheap.
    return TickerMode(
      enabled: shouldTick,
      child: RepaintBoundary(child: art),
    );
  }

  Widget _buildArt(SokoIllustration kind, double size, Color? color) {
    switch (kind) {
      case SokoIllustration.emptyCart:
        return EmptyCartArt(size: size, color: color);
      case SokoIllustration.emptyWishlist:
        return EmptyWishlistArt(size: size, color: color);
      case SokoIllustration.emptyOrders:
        return EmptyOrdersArt(size: size, color: color);
      case SokoIllustration.emptyChat:
        return EmptyChatArt(size: size, color: color);
      case SokoIllustration.emptySearch:
        return EmptySearchArt(size: size, color: color);
      case SokoIllustration.emptyCategory:
        return EmptyCategoryArt(size: size, color: color);
      case SokoIllustration.emptyProducts:
        return EmptyProductsArt(size: size, color: color);
      case SokoIllustration.emptyMusic:
        return EmptyMusicArt(size: size, color: color);
      case SokoIllustration.emptyLocation:
        return EmptyLocationArt(size: size, color: color);
      case SokoIllustration.emptyNotifications:
        return EmptyNotificationsArt(size: size, color: color);
      case SokoIllustration.emptyTransactions:
        return EmptyTransactionsArt(size: size, color: color);
      case SokoIllustration.emptyShipping:
        return EmptyShippingArt(size: size, color: color);
      case SokoIllustration.noInternet:
        return NoInternetArt(size: size, color: color);
      case SokoIllustration.upload:
        return UploadArt(size: size, color: color);
      case SokoIllustration.download:
        return DownloadArt(size: size, color: color);
      case SokoIllustration.paymentPending:
        return PaymentPendingArt(size: size, color: color);
      case SokoIllustration.paymentProcessing:
        return PaymentProcessingArt(size: size, color: color);
      case SokoIllustration.paymentSuccess:
      case SokoIllustration.orderConfirmed:
        return SuccessCheckArt(size: size, color: color);
      case SokoIllustration.sellerDashboard:
        return SellerDashboardArt(size: size, color: color);
      case SokoIllustration.productCreated:
        return ProductCreatedArt(size: size, color: color);
      case SokoIllustration.kycPending:
        return KycPendingArt(size: size, color: color);
      case SokoIllustration.kycVerified:
        return KycVerifiedArt(size: size, color: color);
      case SokoIllustration.recentlyViewed:
        return RecentlyViewedArt(size: size, color: color);
      case SokoIllustration.splash:
        return SplashArt(size: size, color: color);
      case SokoIllustration.onboarding:
        return OnboardingArt(size: size, color: color);
      case SokoIllustration.homePromo:
        return HomePromoArt(size: size, color: color);
      case SokoIllustration.productLoading:
        return ProductLoadingArt(size: size, color: color);
      case SokoIllustration.errorRetry:
        return ErrorRetryArt(size: size, color: color);
    }
  }
}

/// Convenience empty state that pairs [DsEmptyState] with an illustration.
class SokoEmptyState extends StatelessWidget {
  const SokoEmptyState({
    super.key,
    required this.illustration,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.tint,
    this.centered = true,
    this.size = 96,
  });

  final SokoIllustration illustration;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? tint;
  final bool centered;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DsEmptyState(
      icon: Icons.inbox_outlined,
      title: title,
      body: body,
      actionLabel: actionLabel,
      onAction: onAction,
      tint: tint,
      centered: centered,
      artwork: SokoAnimatedIllustration(illustration, size: size, color: tint),
    );
  }
}

class SokoLoadingIllustration extends StatelessWidget {
  const SokoLoadingIllustration({super.key, this.size = 96, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SokoAnimatedIllustration(SokoIllustration.productLoading, size: size, color: color);
  }
}

class SokoUploadIllustration extends StatelessWidget {
  const SokoUploadIllustration({super.key, this.size = 96, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SokoAnimatedIllustration(SokoIllustration.upload, size: size, color: color);
  }
}

class SokoSuccessIllustration extends StatelessWidget {
  const SokoSuccessIllustration({super.key, this.size = 96, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SokoAnimatedIllustration(SokoIllustration.paymentSuccess, size: size, color: color);
  }
}

class SokoErrorIllustration extends StatelessWidget {
  const SokoErrorIllustration({super.key, this.size = 96, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SokoAnimatedIllustration(SokoIllustration.errorRetry, size: size, color: color);
  }
}
