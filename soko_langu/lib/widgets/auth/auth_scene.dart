
import 'package:flutter/material.dart';

import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../staggered_fade_in.dart';

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

    return Scaffold(
      backgroundColor: cs.surface,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 920;

          if (desktop) {
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _BrandPanel(
                      logo: logo,
                      cs: cs,
                    ),
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    child: Stack(
                      children: [
                        if (leading != null)
                          Positioned(
                            left: 24,
                            top: 18,
                            child: leading!,
                          ),
                        Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                              vertical: 36,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 460),
                              child: _FormColumn(
                                heading: heading,
                                subtitle: subtitle,
                                child: child,
                                footer: footer,
                                cs: cs,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  left: AppInsets.xl,
                  right: AppInsets.xl,
                  top: AppInsets.sm,
                  bottom:
                      MediaQuery.of(context).viewInsets.bottom + AppInsets.xl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Stack(
                    children: [
                      if (leading != null)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: leading!,
                        ),
                      Padding(
                        padding:
                            EdgeInsets.only(top: leading == null ? 0 : 44),
                        child: _FormColumn(
                          heading: heading,
                          subtitle: subtitle,
                          child: child,
                          footer: footer,
                          cs: cs,
                          logo: logo,
                          showLogo: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  final String heading;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final ColorScheme cs;
  final Widget? logo;
  final bool showLogo;

  const _FormColumn({
    required this.heading,
    required this.subtitle,
    required this.child,
    required this.footer,
    required this.cs,
    this.logo,
    this.showLogo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLogo) ...[
          Center(child: _Logo(logo: logo)),
          const SizedBox(height: AppSpacing.s5),
        ],
        StaggeredFadeIn(
          index: 0,
          child: Text(
            heading,
            textAlign: TextAlign.center,
            style: AppTypography.screenTitle(cs.onSurface),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          StaggeredFadeIn(
            index: 1,
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s5),
        StaggeredFadeIn(
          index: 2,
          child: AuthCard(child: child),
        ),
        if (footer != null) ...[
          const SizedBox(height: AppSpacing.s4),
          StaggeredFadeIn(index: 3, child: footer!),
        ],
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  final Widget? logo;
  final ColorScheme cs;

  const _BrandPanel({
    required this.logo,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(56),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Logo(logo: logo, size: 76),
                const SizedBox(height: 28),
                Text(
                  'Soko Vibe',
                  style: AppTypography.brandTitle(cs.primary).copyWith(
                    fontSize: 40,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Soko la bidhaa halisi, lililojengwa kwa urahisi na uaminifu.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tafuta bidhaa, chagua muuzaji na lipa kwa ulinzi wa malipo. Uzoefu mmoja rahisi kwenye simu na web.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 28),
                const _TrustLine(
                  icon: Icons.lock_outline_rounded,
                  title: 'Protected payments',
                ),
                const SizedBox(height: 12),
                const _TrustLine(
                  icon: Icons.verified_user_outlined,
                  title: 'Verified sellers',
                ),
                const SizedBox(height: 12),
                const _TrustLine(
                  icon: Icons.local_shipping_outlined,
                  title: 'Delivery support',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustLine extends StatelessWidget {
  final IconData icon;
  final String title;

  const _TrustLine({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: cs.primary),
        ),
        const SizedBox(width: 11),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  final Widget? logo;
  final double size;

  const _Logo({
    this.logo,
    this.size = 78,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(
        Icons.storefront_outlined,
        color: cs.primary,
        size: size * 0.46,
      ),
    );

    if (logo != null) {
      return logo!;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.asset(
        'assets/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

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
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: cs.brightness == Brightness.dark ? 0.16 : 0.045,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
