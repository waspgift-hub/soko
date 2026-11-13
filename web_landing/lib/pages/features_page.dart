import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/sections/page_sections.dart';

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final sw = AppStrings.of(context).isSw;
    final dev = sw ? 'Inaendelezwa' : 'In development';
    final plan = sw ? 'Imepangwa' : 'Planned';
    final items = [
      (
        Icons.search,
        sw ? 'Ugunduzi wa Bidhaa' : 'Shopping & Discovery',
        sw
            ? 'Utafutaji na ugunduzi wa bidhaa/huduma uliopangwa kwa urahisi.'
            : 'Search and discovery for products/services designed for simplicity.',
        dev,
      ),
      (
        Icons.store,
        sw ? 'Zana za Wauzaji' : 'Seller Tools',
        sw
            ? 'Wasifu wa muuzaji na uwasilishaji wa bidhaa; maelezo yatathibitishwa uzinduzi.'
            : 'Seller profiles and product presentation; details confirmed at launch.',
        plan,
      ),
      (
        Icons.groups_outlined,
        sw ? 'Biashara ya Kijamii' : 'Social Commerce',
        sw
            ? 'Vipengele vya mwingiliano na ugunduzi wa kijamii vinaandaliwa kwa uwazi.'
            : 'Interaction and social discovery features are being designed responsibly.',
        plan,
      ),
      (
        Icons.perm_media_outlined,
        sw ? 'Maudhui ya Bidhaa' : 'Product Media',
        sw
            ? 'Picha na video za bidhaa pale jukwaa linapounga mkono.'
            : 'Product images and video where supported by the platform.',
        dev,
      ),
      (
        Icons.payments_outlined,
        sw ? 'Malipo na Miamala' : 'Payments & Transactions',
        sw
            ? 'Vitaelezwa tu kama vinapatikana baada ya uthibitishaji wa kiufundi na kibiashara.'
            : 'Will only be described as available after technical and business verification.',
        plan,
      ),
      (
        Icons.verified_user_outlined,
        sw ? 'Uaminifu na Usalama' : 'Trust & Security',
        sw
            ? 'Sera, udhibiti wa ufikiaji, na mawasiliano ya ulinzi kulingana na hali halisi.'
            : 'Policies, access controls, and protection messaging based on actual status.',
        dev,
      ),
      (
        Icons.notifications_none,
        sw ? 'Arifa' : 'Notifications',
        sw
            ? 'Taarifa za uzinduzi kwenye tovuti; arifa za programu zitategemea uzinduzi.'
            : 'Launch updates on the website; app notifications depend on launch.',
        dev,
      ),
      (
        Icons.auto_awesome_outlined,
        sw ? 'Uzoefu wa AI' : 'AI-powered Experiences',
        sw
            ? 'Vipengele vyovyote vya AI vitaelezwa tu vikitekelezwa au kupangwa rasmi.'
            : 'Any AI features will be described only when implemented or officially planned.',
        plan,
      ),
    ];
    return SiteShell(
      currentPath: AppRoutes.features,
      child: Column(
        children: [
          PageHero(
            titleKey: 'page_features_title',
            subKey: 'highlights_sub',
            badgeKey: 'badge_under_dev',
          ),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 980 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 170,
                  ),
                  itemBuilder: (_, i) => SimpleInfoCard(
                    icon: items[i].$1,
                    title: items[i].$2,
                    body: items[i].$3,
                    badge: items[i].$4,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
