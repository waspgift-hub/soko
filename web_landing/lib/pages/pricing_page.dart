import 'package:flutter/material.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/sections/page_sections.dart';
import '../localization/app_strings.dart';

class PricingPage extends StatelessWidget {
  const PricingPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentPath: AppRoutes.pricing,
      child: Column(
        children: [
          PageHero(
            titleKey: 'page_pricing_title',
            subKey: 'page_pricing_pending',
            badgeKey: 'badge_under_dev',
          ),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          size: 40,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.str('page_pricing_pending'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, height: 1.6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.of(context).isSw
                              ? 'Hatuchapishi bei au mipango isiyothibitishwa.'
                              : 'We do not publish unverified pricing or plans.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
