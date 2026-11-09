import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/sections/page_sections.dart';

class SellersPage extends StatelessWidget {
  const SellersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final sw = AppStrings.of(context).isSw;
    return SiteShell(
      currentPath: AppRoutes.sellers,
      child: Column(
        children: [
          PageHero(
            titleKey: 'page_sellers_title',
            subKey: 'sellers_preview_body',
            badgeKey: 'badge_under_dev',
            trailing: FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamed(AppRoutes.home, arguments: {'scrollTo': 'register'}),
              child: Text(
                sw ? 'Jiandikishe kama Muuzaji' : 'Register Seller Interest',
              ),
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
                    icon: Icons.storefront,
                    title: sw ? 'Kuwasilisha bidhaa' : 'Presenting products',
                    body: sw
                        ? 'Lengo ni kusaidia wauzaji kuonyesha bidhaa na maelezo kwa uwazi. Hatutoi ahadi za mauzo.'
                        : 'The goal is to help sellers present products and details clearly. We do not promise sales.',
                  ),
                  ContentBlock(
                    icon: Icons.photo_library_outlined,
                    title: sw ? 'Kushiriki maudhui' : 'Sharing media',
                    body: sw
                        ? 'Picha na video za bidhaa zinaweza kuungwa mkono kulingana na uwezo wa jukwaa.'
                        : 'Product images and video may be supported depending on platform capabilities.',
                  ),
                  ContentBlock(
                    icon: Icons.badge_outlined,
                    title: sw ? 'Utambulisho wa muuzaji' : 'Seller identity',
                    body: sw
                        ? 'Wasifu na vipengele vya uaminifu vitaelezwa kulingana na hali halisi ya utekelezaji.'
                        : 'Profiles and trust features will be communicated based on actual implementation status.',
                  ),
                  ContentBlock(
                    icon: Icons.trending_up,
                    title: sw ? 'Ukuaji wa biashara' : 'Business growth',
                    body: sw
                        ? 'Mwonekano na matokeo hutegemea mambo mengi; Soko Vibe haitoi dhamana ya mauzo, mapato, au mwonekano.'
                        : 'Visibility and outcomes depend on many factors; Soko Vibe does not guarantee sales, revenue, or visibility.',
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
