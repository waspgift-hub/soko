import 'package:flutter/material.dart';

class LiveBadge extends StatelessWidget {
  final double size;

  const LiveBadge({super.key, this.size = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.6,
        vertical: size * 0.25,
      ),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(size * 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: size * 0.3),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
