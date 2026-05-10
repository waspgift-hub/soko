import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  final String? tier;
  final double size;

  const VerifiedBadge({super.key, this.tier, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (tier != 'silver') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Icon(Icons.verified, color: Colors.black, size: size),
    );
  }
}
