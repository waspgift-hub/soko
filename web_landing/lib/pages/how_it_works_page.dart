import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/sections/page_sections.dart';

class HowItWorksPage extends StatelessWidget {
  const HowItWorksPage({super.key});
  @override
  Widget build(BuildContext context) {
    final sw = AppStrings.of(context).isSw;
    return SiteShell(
      currentPath: AppRoutes.howItWorks,
      child: Column(
        children: [
          PageHero(
            titleKey: 'page_how_title',
            subKey: 'how_note',
            badgeKey: 'badge_under_dev',
          ),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentBlock(
                    icon: Icons.search,
                    title: sw ? '1. Gundua' : '1. Discover',
                    body: sw
                        ? 'Vinavyoandaliwa: kutafuta na kuchunguza bidhaa na huduma. Utaratibu halisi utathibitishwa uzinduzi.'
                        : 'Planned: find and explore products and services. Final behavior will be confirmed at launch.',
                  ),
                  ContentBlock(
                    icon: Icons.forum_outlined,
                    title: sw ? '2. Ungana' : '2. Connect',
                    body: sw
                        ? 'Vinavyoandaliwa: kuchunguza wasifu wa wauzaji na maelezo ya bidhaa kupitia njia zitakazopatikana na kuthibitishwa.'
                        : 'Planned: explore seller profiles and product details through channels that are available and verified.',
                  ),
                  ContentBlock(
                    icon: Icons.shopping_bag_outlined,
                    title: sw ? '3. Nunua / Shirikiana' : '3. Shop / Engage',
                    body: sw
                        ? 'Vipengele vya ununuzi, malipo, utoaji, na ukamilishaji wa miamala vitaelezwa kuwa vinapatikana tu vikiwa vimethibitishwa na kufanya kazi.'
                        : 'Buying, payments, delivery, and transaction completion features will only be described as available when verified and operational.',
                  ),
                  ContentBlock(
                    icon: Icons.people_outline,
                    title: sw ? 'Kwa Wanunuzi' : 'For Buyers',
                    body: sw
                        ? 'Tunajenga uzoefu wa ugunduzi na maamuzi yaliyo wazi. Jiunge na orodha kupata taarifa.'
                        : 'We are building a discovery and decision experience with clarity. Join the waitlist for updates.',
                  ),
                  ContentBlock(
                    icon: Icons.storefront_outlined,
                    title: sw ? 'Kwa Wauzaji' : 'For Sellers',
                    body: sw
                        ? 'Tunajenga njia za kuwasilisha bidhaa na kufikia wanunuzi. Hatutoi ahadi za mauzo au mapato.'
                        : 'We are building ways to present products and reach buyers. We do not promise sales or revenue.',
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
