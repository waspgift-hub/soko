import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import '../../theme/app_colors.dart';
import '../animated_reveal.dart';
import '../responsive_container.dart';

class PageHero extends StatelessWidget {
  final String titleKey;
  final String? subKey;
  final String? badgeKey;
  final Widget? trailing;
  const PageHero({
    super.key,
    required this.titleKey,
    this.subKey,
    this.badgeKey,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B141A), SokoBrand.deepGreen, SokoBrand.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ResponsiveContainer(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
        child: AnimatedReveal(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badgeKey != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      context.str(badgeKey!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                if (badgeKey != null) const SizedBox(height: 18),
                Text(
                  context.str(titleKey),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    height: 1.08,
                  ),
                ),
                if (subKey != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    context.str(subKey!),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 17,
                      height: 1.55,
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: 20),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SimpleInfoCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final String? badge;
  const SimpleInfoCard({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: SokoBrand.deepGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: SokoBrand.deepGreen),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SokoBrand.paper,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: SokoBrand.line),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: SokoBrand.muted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: SokoBrand.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: SokoBrand.muted,
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContentBlock extends StatelessWidget {
  final String title;
  final String body;
  final IconData? icon;
  const ContentBlock({
    super.key,
    required this.title,
    required this.body,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedReveal(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: SokoBrand.deepGreen),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: SokoBrand.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(
                      color: SokoBrand.muted,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
