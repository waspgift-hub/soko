import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});
  @override
  Widget build(BuildContext context) {
    final isSw = AppStrings.of(context).isSw;
    return SiteShell(
      currentPath: AppRoutes.faq,
      child: Column(
        children: [
          PageHero(titleKey: 'page_faq_title', badgeKey: 'badge_under_dev'),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in fullFaqItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          title: Text(
                            context.str(item.qKey),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            18,
                            0,
                            18,
                            18,
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.str(item.aKey),
                                style: const TextStyle(height: 1.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    isSw
                        ? 'Majibu yanaakisi hali ya sasa ya maendeleo. Vipengele vitaelezwa kuwa vinapatikana tu vikithibitishwa.'
                        : 'Answers reflect current development status. Features are described as available only when verified.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
          colors: [Color(0xFF0B141A), Color(0xFF008069), Color(0xFF00A884)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ResponsiveContainer(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
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
                  ),
                  child: Text(
                    context.str(badgeKey!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (badgeKey != null) const SizedBox(height: 16),
              Text(
                context.str(titleKey),
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: Colors.white),
              ),
              if (subKey != null) ...[
                const SizedBox(height: 12),
                Text(
                  context.str(subKey!),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(height: 16), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
