import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  final String? tier;
  final double size;
  final bool isAdmin;

  const VerifiedBadge({
    super.key,
    this.tier,
    this.size = 16,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    if (tier != 'silver') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Icon(
        Icons.verified,
        color: isAdmin ? Colors.black : Colors.blue[600],
        size: size,
      ),
    );
  }
}
