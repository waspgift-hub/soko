import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/sections/page_sections.dart';

class BuyersPage extends StatelessWidget {
  const BuyersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final sw = AppStrings.of(context).isSw;
    return SiteShell(
      currentPath: AppRoutes.buyers,
      child: Column(
        children: [
          PageHero(
            titleKey: 'page_buyers_title',
            subKey: 'buyers_preview_body',
            badgeKey: 'badge_under_dev',
            trailing: FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamed(AppRoutes.home, arguments: {'scrollTo': 'register'}),
              child: Text(context.str('cta_notify')),
            ),
          ),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentBlock(
                    icon: Icons.search,
                    title: sw ? 'Kugundua bidhaa' : 'Discovering products',
                    body: sw
                        ? 'Tunalenga kufanya ugunduzi wa bidhaa na huduma uwe rahisi na wenye mpangilio.'
                        : 'We aim to make discovering products and services simple and organized.',
                  ),
                  ContentBlock(
                    icon: Icons.person_search_outlined,
                    title: sw ? 'Kuwapata wauzaji' : 'Finding sellers',
                    body: sw
                        ? 'Taarifa za muuzaji na maudhui ya bidhaa vitaonyeshwa kwa uwazi kadri vitakavyopatikana.'
                        : 'Seller information and product content will be presented clearly as available.',
                  ),
                  ContentBlock(
                    icon: Icons.compare_arrows,
                    title: sw ? 'Kulinganisha chaguo' : 'Comparing options',
                    body: sw
                        ? 'Vipengele vya kulinganisha vitategemea utekelezaji uliothibitishwa.'
                        : 'Comparison features will depend on verified implementation.',
                  ),
                  ContentBlock(
                    icon: Icons.shield_outlined,
                    title: sw
                        ? 'Uzoefu unaolenga uaminifu'
                        : 'Trust-focused experience',
                    body: sw
                        ? 'Ulinzi maalum wa miamala utaelezwa tu ukiwa umehakikiwa na unafanya kazi.'
                        : 'Specific transaction protections will be described only when verified and operational.',
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
