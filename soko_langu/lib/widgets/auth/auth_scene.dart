import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../staggered_fade_in.dart';

/// Full-page shell for authentication screens.
///
/// Modern gradient hero: brand-green panel on top with the logo, heading and
/// subtitle in white, a floating [AuthCard] overlapping its base, and a soft
/// tinted canvas behind — matched for both light and dark themes.
class AuthScene extends StatelessWidget {
  final Widget? leading;
  final Widget? logo;
  final String heading;
  final String? subtitle;
  final Widget? footer;
  final Widget child;

  const AuthScene({
    super.key,
    this.leading,
    this.logo,
    required this.heading,
    this.subtitle,
    this.footer,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    final canvas = isDark
        ? const [Color(0xFF0B0B0B), Color(0xFF11150F)]
        : const [Color(0xFFF4FBF6), Color(0xFFFFFFFF)];

    return Scaffold(
      // Soft brand-tinted canvas keeps the page cohesive while the card stays
      // neutral, so inputs keep full contrast in both themes.
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: canvas,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: AppInsets.xl,
                right: AppInsets.xl,
                top: AppInsets.sm,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppInsets.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StaggeredFadeIn(
                      index: 0,
                      child: _GradientHero(
                        leading: leading,
                        logo: logo,
                        heading: heading,
                        subtitle: subtitle,
                      ),
                    ),
                    // Card floats over the hero base for a layered depth look.
                    Transform.translate(
                      offset: const Offset(0, -AppSpacing.s7),
                      child: StaggeredFadeIn(index: 1, child: child),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      StaggeredFadeIn(index: 2, child: footer!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand-green gradient panel with the auth identity details.
class _GradientHero extends StatelessWidget {
  final Widget? leading;
  final Widget? logo;
  final String heading;
  final String? subtitle;

  const _GradientHero({
    this.leading,
    this.logo,
    required this.heading,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // #00C853 (light) / #009624 (deep) is the commerce CTA ramp — the hero
    // switches to the deep end in dark mode so white text keeps ≥4.5:1.
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final gradient = isDark
        ? const [Color(0xFF00A340), Color(0xFF007A2F)]
        : const [Color(0xFF00C853), Color(0xFF009624)];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius2.xxl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius2.xxl),
        ),
        child: Stack(
          children: [
            // Soft decorative blobs — no repaint, static gradient only.
            Positioned(
              right: -60,
              top: -70,
              child: _Blob(
                size: 180,
                color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.14),
              ),
            ),
            Positioned(
              left: -40,
              bottom: -80,
              child: _Blob(
                size: 160,
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppInsets.xl,
                AppInsets.sm,
                AppInsets.xl,
                44,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back affordance pinned to the panel, forced white so it
                  // stays visible on brand green in both themes.
                  IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: leading ?? const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Center(child: _Logo(logo: logo)),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    heading,
                    textAlign: TextAlign.center,
                    style: AppTypography.screenTitle(Colors.white),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static tinted circle used for decorative gradient depth.
class _Blob extends StatelessWidget {
  final double size;
  final Color color;

  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _Logo extends StatelessWidget {
  final Widget? logo;

  const _Logo({this.logo});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: const Icon(
        Icons.shopping_bag_rounded,
        size: 38,
        color: Colors.white,
      ),
    );
    return Center(
      child:
          logo ??
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/app_icon.png',
                width: 78,
                height: 78,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
          ),
    );
  }
}

/// Solid card that hosts auth forms; overlaps the gradient hero base.
class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppInsets.xl),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius2.xxl),
        border: Border.all(color: cs.brandBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: cs.brightness == Brightness.dark ? 0.45 : 0.1,
            ),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}
