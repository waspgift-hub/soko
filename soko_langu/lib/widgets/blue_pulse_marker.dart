import 'package:flutter/material.dart';

class BluePulseMarker extends StatefulWidget {
  final double size;
  const BluePulseMarker({super.key, this.size = 48});

  @override
  State<BluePulseMarker> createState() => _BluePulseMarkerState();
}

class _BluePulseMarkerState extends State<BluePulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 0.9)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        final ringAlpha = _pulseAnim.value;
        return SizedBox(
          width: s,
          height: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.15 * ringAlpha),
                ),
              ),
              Container(
                width: s * 0.7,
                height: s * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.3 * ringAlpha),
                ),
              ),
              Container(
                width: s * 0.35,
                height: s * 0.35,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1A73E8),
                ),
              ),
              Container(
                width: s * 0.15,
                height: s * 0.15,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
