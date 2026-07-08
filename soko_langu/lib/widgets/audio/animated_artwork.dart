import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedArtwork extends StatefulWidget {
  final String? imageUrl;
  final double size;
  final bool isPlaying;
  final Color fallbackColor;
  const AnimatedArtwork({super.key, this.imageUrl, this.size = 280, this.isPlaying = false, this.fallbackColor = Colors.blue});
  @override
  State<AnimatedArtwork> createState() => _AnimatedArtworkState();
}
class _AnimatedArtworkState extends State<AnimatedArtwork> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    if (widget.isPlaying) _ctrl.repeat();
  }
  @override
  void didUpdateWidget(AnimatedArtwork old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctrl.isAnimating) _ctrl.repeat();
    if (!widget.isPlaying && _ctrl.isAnimating) _ctrl.stop();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: child,
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.fallbackColor.withValues(alpha: 0.2),
          image: widget.imageUrl != null ? DecorationImage(image: NetworkImage(widget.imageUrl!), fit: BoxFit.cover) : null,
          boxShadow: [BoxShadow(color: widget.fallbackColor.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: 4)],
        ),
        child: widget.imageUrl == null ? Icon(Icons.music_note_rounded, size: widget.size * 0.4, color: Colors.white.withValues(alpha: 0.3)) : null,
      ),
    );
  }
}
