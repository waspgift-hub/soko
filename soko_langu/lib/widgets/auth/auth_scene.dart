import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../staggered_fade_in.dart';

/// Full-page shell for authentication screens.
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              left: AppInsets.xl,
              right: AppInsets.xl,
              top: AppSpacing.s2,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppInsets.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Stack(
                children: [
                  if (leading != null)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: leading!,
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (leading != null) const SizedBox(height: 48),
                      Center(child: _Logo(logo: logo)),
                      const SizedBox(height: AppSpacing.s6),
                      StaggeredFadeIn(
                        index: 0,
                        child: Text(
                          heading,
                          textAlign: TextAlign.center,
                          style: AppTypography.screenTitle(cs.onSurface),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.s2 + 2),
                        StaggeredFadeIn(
                          index: 1,
                          child: Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s6),
                      StaggeredFadeIn(index: 2, child: child),
                      if (footer != null) ...[
                        const SizedBox(height: AppSpacing.s5),
                        StaggeredFadeIn(index: 3, child: footer!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final Widget? logo;

  const _Logo({this.logo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Icon(Icons.shopping_bag, size: 40, color: cs.primary),
    );
    return Center(
      child: logo ??
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Image.asset(
              'assets/app_icon.png',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
    );
  }
}

/// Solid card that hosts auth forms.
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
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: child,
    );
  }
}