import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../extensions/context_tr.dart';
import '../../../models/product_model.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/ds/ds.dart';
import '../../../widgets/product_cached_image.dart';
import '../boost_tiers.dart';

/// Dark, always-dark hero that anchors the boost screen: the value proposition,
/// a live preview of the listing once it is boosted, and the reassurance strip.
///
/// The panel stays dark in both themes on purpose. It is the one place on the
/// screen allowed to break out of the canvas, which is what makes the pay CTA
/// below read as the primary action rather than just another green box.
class BoostHeroPanel extends StatelessWidget {
  final Product? product;
  final bool canSwitchProduct;
  final VoidCallback onTapProduct;

  const BoostHeroPanel({
    super.key,
    required this.product,
    required this.canSwitchProduct,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius2.xxl),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111613), Color(0xFF050706)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              right: -70,
              top: -60,
              child: _Aurora(size: 220, color: Color(0xFF00C853)),
            ),
            const Positioned(
              left: -90,
              bottom: -110,
              child: _Aurora(size: 240, color: Color(0xFF00E676)),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DsBadge(
                        label: context.tr('boost_hero_eyebrow'),
                        color: const Color(0xFF00C853),
                        textColor: Colors.black,
                        icon: Icons.rocket_launch_rounded,
                      ),
                      const Spacer(),
                      const DsBadge(
                        label: 'PRO',
                        color: Color(0x1AFFFFFF),
                        textColor: Color(0xFFD8D8D8),
                        icon: Icons.verified_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    context.tr('boost_hero_title'),
                    style: AppTypography.brandTitle(
                      Colors.white,
                    ).copyWith(fontSize: 28, height: 1.12),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    context.tr('boost_hero_subtitle'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  _ProductPreview(
                    product: product,
                    accent: scheme.primary,
                    onTap: onTapProduct,
                    canSwitch: canSwitchProduct,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  const _HeroReassuranceStrip(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft radial glow behind the hero copy. Cheaper than a BackdropFilter and it
/// never fights the text layered on top.
class _Aurora extends StatelessWidget {
  const _Aurora({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// What the listing looks like once the boost is live. Doubles as the product
/// switcher: tapping it opens the picker, so selection and preview can never
/// disagree about which product is being boosted.
class _ProductPreview extends StatelessWidget {
  const _ProductPreview({
    required this.product,
    required this.accent,
    required this.onTap,
    required this.canSwitch,
  });

  final Product? product;
  final Color accent;
  final VoidCallback onTap;
  final bool canSwitch;

  @override
  Widget build(BuildContext context) {
    final item = product;
    final enabled = canSwitch && item != null;

    return AnimatedPress(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      pressedScale: 0.985,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius2.xl),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: item == null
                        ? Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Colors.white54,
                            ),
                          )
                        : ProductCachedImage(
                            url: item.images.isNotEmpty ? item.images[0] : null,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item?.name ?? context.tr('boost_hero_no_product'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item == null
                            ? ''
                            : context.formatPriceInt(item.price.toInt(), currencyOverride: 'TZS'),
                        style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (canSwitch)
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.swap_vert_rounded, size: 18, color: Colors.white70),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s3),
            Row(
              children: [
                DsBadge(
                  label: context.tr('boost_hero_badge'),
                  color: const Color(0xFF00C853),
                  textColor: Colors.black,
                  icon: Icons.rocket_launch_rounded,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    context.tr('boost_hero_preview_line'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
                  ),
                ),
                const DsBadge(
                  label: '#1',
                  color: Color(0xFFF59E0B),
                  textColor: Colors.black,
                  icon: Icons.emoji_events_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroReassuranceStrip extends StatelessWidget {
  const _HeroReassuranceStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFF00C853)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            context.tr('boost_trust_instant'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5),
          ),
        ),
        const Text('�', style: TextStyle(color: Color(0x4DFFFFFF))),
        const SizedBox(width: AppSpacing.s2),
        Text(
          context.tr('boost_trust_no_subscription'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5),
        ),
      ],
    );
  }
}

/// Animated counting number used by the reach estimator.
class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.style,
    this.duration = Motion.countUp,
  });

  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) =>
          Text(formatBoostCount((widget.value * _curve.value).round()), style: widget.style),
    );
  }
}
