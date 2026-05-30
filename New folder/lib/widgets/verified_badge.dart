import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  final String? tier;
  final double size;
  final bool isAdmin;
  final bool isVerified;

  const VerifiedBadge({
    super.key,
    this.tier,
    this.size = 16,
    this.isAdmin = false,
    this.isVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = tier == 'silver' || tier == 'premium' || isVerified;
    if (!showBadge) return const SizedBox.shrink();

    Color badgeColor;
    if (isVerified) {
      badgeColor = Colors.green;
    } else if (tier == 'premium') {
      badgeColor = Colors.amber;
    } else {
      badgeColor = isAdmin ? Colors.black : Colors.blue[600]!;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Icon(
        Icons.verified,
        color: badgeColor,
        size: size,
      ),
    );
  }
}
