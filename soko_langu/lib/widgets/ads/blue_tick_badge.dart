import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/seller_verification.dart';
import '../../services/seller_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';
import '../ds/ds_verified_check.dart';

/// The Blue Tick badge.
///
/// One widget for every surface — product cards, seller profiles, search
/// results, comments, reviews, orders and chat — so the trust signal is
/// visually identical everywhere and cannot drift per screen.
///
/// The tick is rendered only from trusted server state resolved by
/// [SellerVerificationService]. There is no `isVerified` boolean parameter, so a
/// call site cannot pass in a locally-assigned trust flag.
///
/// Size defaults are deliberately small (14dp inline, 16dp on a profile header)
/// so the badge informs without dominating the seller's name or avatar.
class BlueTickBadge extends StatefulWidget {
  const BlueTickBadge({
    super.key,
    required this.sellerId,
    this.size = 14,
    this.animate = false,
    this.semanticLabel,
  });

  /// uid of the seller whose tick should be shown.
  final String sellerId;
  final double size;

  /// Enables the first-appearance pulse. Off by default because a pulse inside a
  /// scrolling product grid is distracting.
  final bool animate;

  final String? semanticLabel;

  @override
  State<BlueTickBadge> createState() => _BlueTickBadgeState();
}

class _BlueTickBadgeState extends State<BlueTickBadge> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SellerVerificationService>().resolve(widget.sellerId);
    });
  }

  @override
  void didUpdateWidget(BlueTickBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId && mounted) {
      context.read<SellerVerificationService>().resolve(widget.sellerId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sellerId.isEmpty) return const SizedBox.shrink();
    // Subscribing to the verification service means a revocation removes the
    // badge without a restart.
    final service = context.watch<SellerVerificationService>();
    if (!service.isBlueTick(widget.sellerId)) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.semanticLabel ?? 'Verified seller',
      child: Padding(
        padding: const EdgeInsets.only(left: 3),
        child: widget.animate
            ? DsVerifiedCheck(size: widget.size, color: cs.brandSuccess)
            : Icon(Icons.verified, size: widget.size, color: cs.brandSuccess),
      ),
    );
  }
}

/// Compact "Verified" pill for surfaces that need the word, not just the glyph
/// (seller profile header, order detail seller row, admin review queues).
///
/// [verification] is passed explicitly rather than resolved from a uid so the
/// same trusted object that drives eligibility drives the label — there is no
/// second, weaker source of truth.
class BlueTickPill extends StatelessWidget {
  const BlueTickPill({
    super.key,
    required this.verification,
    this.label,
    this.compact = false,
  });

  final SellerVerification? verification;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v = verification;
    if (v == null || !v.isBlueTickActive) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Ds.sp2 : Ds.sp3,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: cs.brandSuccess.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Ds.rFull),
        border: Border.all(color: cs.brandSuccess.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: compact ? 11 : 13, color: cs.brandSuccess),
          const SizedBox(width: 4),
          Text(
            label ?? 'Verified',
            style: AppTypography.statusChip(cs.brandSuccess).copyWith(
              fontSize: compact ? AppFontSize.xs : AppFontSize.sm,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
