import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../router/app_router.dart';
import '../widgets/layout/site_shell.dart';
import '../widgets/responsive_container.dart';
import '../widgets/sections/page_sections.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    final isSw = AppStrings.of(context).isSw;
    return SiteShell(
      currentPath: AppRoutes.about,
      child: Column(
        children: [
          PageHero(
            titleKey: 'page_about_title',
            subKey: 'about_body',
            badgeKey: 'badge_under_dev',
          ),
          ResponsiveContainer(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentBlock(
                    icon: Icons.visibility_outlined,
                    title: isSw ? 'Maono Yetu' : 'Our Vision',
                    body: isSw
                        ? 'Kusaidia kufanya biashara ya kidijitali Tanzania kuwa rahisi, yenye muunganiko, na rahisi kuamini kadri jukwaa linavyokomaa.'
                        : 'To help make digital commerce in Tanzania simpler, more connected, and easier to trust as the platform matures.',
                  ),
                  ContentBlock(
                    icon: Icons.flag_outlined,
                    title: isSw ? 'Dhamira Yetu' : 'Our Mission',
                    body: isSw
                        ? 'Kujenga uzoefu wa soko unaowaunganisha wanunuzi na wauzaji kupitia ugunduzi wazi wa bidhaa, muundo unaowajibika wa jukwaa, na zana za kidijitali zinazofaa.'
                        : 'To build a marketplace experience that brings buyers and sellers together through clear product discovery, responsible platform design, and practical digital tools.',
                  ),
                  ContentBlock(
                    icon: Icons.favorite_border,
                    title: isSw ? 'Maadili Yetu' : 'Our Values',
                    body: isSw
                        ? 'Uwazi, uaminifu, urahisi, heshima kwa watumiaji, na ukuaji makini. Tunawasilisha vipengele kulingana na utekelezaji uliothibitishwa na utayari wa uzinduzi.'
                        : 'Clarity, trust, simplicity, respect for users, and careful growth. We communicate features based on verified implementation and launch readiness.',
                  ),
                  ContentBlock(
                    icon: Icons.lightbulb_outline,
                    title: isSw
                        ? 'Tatizo Tunalolishughulikia'
                        : 'The Problem We Are Addressing',
                    body: isSw
                        ? 'Wanunuzi na wauzaji wengi wanahitaji njia iliyo wazi zaidi ya kugundua bidhaa, kuwasilisha matoleo, na kuungana mtandaoni. Soko Vibe inaendelezwa kuboresha uzoefu huo hatua kwa hatua.'
                        : 'Many buyers and sellers need a clearer way to discover products, present offerings, and connect online. Soko Vibe is being developed to improve that experience step by step.',
                  ),
                  ContentBlock(
                    icon: Icons.handshake_outlined,
                    title: isSw ? 'Ahadi Yetu' : 'Our Commitment',
                    body: isSw
                        ? 'Tunalenga kuwahudumia wanunuzi na wauzaji kwa mawasiliano ya uwazi, uzoefu wenye manufaa, na sera zinazoakisi jinsi jukwaa linavyofanya kazi.'
                        : 'We aim to serve buyers and sellers with transparent communication, useful experiences, and policies that reflect how the platform actually works.',
                  ),
                  ContentBlock(
                    icon: Icons.rocket_launch_outlined,
                    title: isSw ? 'Mwelekeo wa Baadaye' : 'Future Direction',
                    body: isSw
                        ? 'Soko Vibe itakua kulingana na maendeleo, mahitaji ya watumiaji, na utayari uliothibitishwa. Taarifa za uzinduzi zitashirikiwa kupitia njia rasmi.'
                        : 'Soko Vibe will evolve based on development progress, user needs, and verified readiness. Launch updates will be shared through official channels.',
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
