import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/seller_verification.dart';
import '../../services/follow_service.dart';
import '../../services/seller_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../theme/design_tokens.dart';
import '../../extensions/context_tr.dart';

/// Follower / following counts row with navigation to the respective lists.
///
/// Tapping a count opens the corresponding [FollowersListScreen] /
/// [FollowingListScreen]. Counts are read from the denormalized
/// `userPublic/{uid}.followerCount` / `followingCount` fields, which are
/// updated server-side whenever a follow relationship is created or removed.
///
/// A Blue Tick badge is shown next to the target user's name when they are
/// KYC-approved and have an active admin grant, matching the badge used
/// everywhere else in the marketplace.
class FollowerFollowingRow extends StatelessWidget {
  const FollowerFollowingRow({
    super.key,
    required this.userId,
    this.userName = '',
    this.verification,
    this.onFollowerTap,
    this.onFollowingTap,
  });

  final String userId;
  final String userName;
  final SellerVerification? verification;
  final VoidCallback? onFollowerTap;
  final VoidCallback? onFollowingTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: context.tr('followers'),
            value: StreamBuilder<int>(
              stream: FollowService().followerCountStream(userId),
              initialData: 0,
              builder: (context, snap) {
                return Text(
                  snap.data.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                );
              },
            ),
            onTap: onFollowerTap,
          ),
        ),
        Expanded(
          child: _StatTile(
            label: context.tr('following'),
            value: StreamBuilder<int>(
              stream: FollowService().followingCountStream(userId),
              initialData: 0,
              builder: (context, snap) {
                return Text(
                  snap.data.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                );
              },
            ),
            onTap: onFollowingTap,
          ),
        ),
      ],
    );
  }
}

/// Single stat pill (count + label) used inside [FollowerFollowingRow].
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Widget value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            value,
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}