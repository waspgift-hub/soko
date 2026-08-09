import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_motion.dart';
import 'animated_press.dart';

/// Rive-style reactive like button: a heart that pops and bursts a handful
/// of hearts outward the moment it becomes liked, then rests (spec §15.7).
class DsLikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback? onPressed;
  final double size;
  final Color? activeColor;
  final Color? idleColor;

  const DsLikeButton({
    super.key,
    required this.isLiked,
    this.onPressed,
    this.size = 24,
    this.activeColor,
    this.idleColor,
  });

  @override
  State<DsLikeButton> createState() => _DsLikeButtonState();
}

class _DsLikeButtonState extends State<DsLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _popScale;
  late final List<_BurstHeart> _hearts;

  static final Random _random = Random();

  static const _palette = [
    Color(0xFFEF5350),
    Color(0xFFEC407A),
    Color(0xFFD32F2F),
    Color(0xFFFF8A80),
    Color(0xFFFFD700),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.celebration);
    // Heart pop: 0 → 1.35 → 0.9 → 1.0 on an easeOutBack feel.
    _popScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.35, end: 0.9),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 30,
      ),
    ]).animate(_controller);
    _hearts = List.generate(8, (_) => _BurstHeart.random());
  }

  @override
  void didUpdateWidget(covariant DsLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fire the burst only when the heart actually turns on.
    if (!oldWidget.isLiked && widget.isLiked) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor ?? cs.error;
    final idleColor = widget.idleColor ?? cs.onSurfaceVariant;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return AnimatedPress(
      onTap: _handleTap,
      child: SizedBox(
        width: widget.size + 16,
        height: widget.size + 16,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (!reduced)
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    if (t <= 0 || t >= 1) {
                      // burst already played out — nothing to paint
                      return const SizedBox.shrink();
                    }
                    return CustomPaint(
                      size: Size.square(widget.size + 16),
                      painter: _HeartBurstPainter(
                        hearts: _hearts,
                        progress: t,
                      ),
                    );
                  },
                ),
              ),
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final scale = reduced || _controller.value == 0
                      ? 1.0
                      : _popScale.value;
                  return Transform.scale(
                    scale: scale,
                    child: AnimatedSwitcher(
                      duration: Motion.ripple,
                      child: Icon(
                        widget.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        key: ValueKey(widget.isLiked),
                        size: widget.size,
                        color: widget.isLiked ? activeColor : idleColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BurstHeart {
  _BurstHeart.random()
      : angle = _DsLikeButtonState._random.nextDouble() * 2 * pi,
        speed = 12 + _DsLikeButtonState._random.nextDouble() * 14,
        size = 4 + _DsLikeButtonState._random.nextDouble() * 3,
        spin = (_DsLikeButtonState._random.nextDouble() - 0.5) * 2.5,
        color = _DsLikeButtonState._palette[_DsLikeButtonState._random.nextInt(
          _DsLikeButtonState._palette.length,
        )];

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
}

class _HeartBurstPainter extends CustomPainter {
  final List<_BurstHeart> hearts;
  final double progress;

  _HeartBurstPainter({required this.hearts, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final h in hearts) {
      final t = progress;
      final opacity = (1 - t).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      final eased = Curves.easeOutCubic.transform(t);
      final pos = center +
          Offset(cos(h.angle), sin(h.angle)) * (h.speed * eased);
      final glyph = Icons.favorite;
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(glyph.codePoint),
          style: TextStyle(
            fontSize: h.size,
            fontFamily: glyph.fontFamily,
            package: glyph.fontPackage,
            color: h.color.withValues(alpha: opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(h.spin * eased);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HeartBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
