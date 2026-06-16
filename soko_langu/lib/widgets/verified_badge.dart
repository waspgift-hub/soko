import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  final double size;
  final Color? color;

  const VerifiedBadge({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Icon(
        Icons.verified,
        size: size,
        color: color ?? Colors.blueAccent,
      ),
    );
  }
}
