import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../sections/ai_delivery_section.dart';
import '../sections/app_faq_final_footer.dart';
import '../sections/boost_security_section.dart';
import '../sections/buyers_sellers_section.dart';
import '../sections/escrow_section.dart';
import '../sections/hero_section.dart';
import '../sections/site_nav.dart';
import '../sections/trust_bar.dart';
import '../sections/why_section.dart';
import '../theme/app_colors.dart';

/// Assembles every section; owns the scroll controller, section anchors,
/// and the locale state shared by the whole page.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scroll = ScrollController();
  final AppStrings _strings = AppStrings();
  bool _scrolled = false;

  final _keys = <String, GlobalKey>{
    'how': GlobalKey(),
    'security': GlobalKey(),
    'sellers': GlobalKey(),
    'boost': GlobalKey(),
    'faq': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _strings.addListener(_onLocale);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _strings.removeListener(_onLocale);
    _scroll.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});
  void _onScroll() {
    final past = _scroll.offset > 8;
    if (past != _scrolled) setState(() => _scrolled = past);
  }

  void _go(String section) {
    final ctx = _keys[section]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppStringsProvider(
      strings: _strings,
      child: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 68,
              backgroundColor: SokoBrand.white,
              flexibleSpace: SiteNav(
                scrolled: _scrolled,
                onNavigate: _go,
                strings: _strings,
              ),
            ),
            const SliverToBoxAdapter(child: HeroSection()),
            const SliverToBoxAdapter(child: TrustBar()),
            SliverToBoxAdapter(
              child:
                  Container(key: _keys['how'], child: const WhySection()),
            ),
            const SliverToBoxAdapter(child: EscrowSection()),
            const SliverToBoxAdapter(child: BuyersSection()),
            SliverToBoxAdapter(
              child: Container(
                  key: _keys['sellers'],
                  child: const SellersSection()),
            ),
            const SliverToBoxAdapter(child: AiSearchSection()),
            const SliverToBoxAdapter(child: DeliverySection()),
            SliverToBoxAdapter(
              child: Container(
                  key: _keys['boost'], child: const BoostSection()),
            ),
            SliverToBoxAdapter(
              child: Container(
                  key: _keys['security'],
                  child: const SecuritySection()),
            ),
            const SliverToBoxAdapter(child: AppSection()),
            SliverToBoxAdapter(
              child:
                  Container(key: _keys['faq'], child: const FaqSection()),
            ),
            SliverToBoxAdapter(
              child: FinalCtaSection(onServices: () => _go('how')),
            ),
            SliverToBoxAdapter(child: SiteFooter(onNavigate: _go)),
          ],
        ),
      ),
    );
  }
}
