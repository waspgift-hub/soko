import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../sections/coming_soon_sections.dart';
import '../sections/site_nav.dart';
import '../theme/app_colors.dart';

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
    'home': GlobalKey(),
    'about': GlobalKey(),
    'features': GlobalKey(),
    'register': GlobalKey(),
    'how': GlobalKey(),
    'faq': GlobalKey(),
    'contact': GlobalKey(),
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
    _scroll.removeListener(_onScroll);
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
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
        alignment: 0.05,
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
              toolbarHeight: 72,
              backgroundColor: SokoBrand.white,
              flexibleSpace: SiteNav(scrolled: _scrolled, onNavigate: _go, strings: _strings, onNotify: () => _go('register')),
            ),
            SliverToBoxAdapter(child: Container(key: _keys['home'], child: HeroSection(onNotify: () => _go('register'), onDiscover: () => _go('about')))),
            SliverToBoxAdapter(child: Container(key: _keys['register'], child: const RegisterSection())),
            SliverToBoxAdapter(child: Container(key: _keys['about'], child: const AboutSection())),
            SliverToBoxAdapter(child: Container(key: _keys['features'], child: const SizedBox.shrink())),
            SliverToBoxAdapter(child: Container(key: _keys['how'], child: const HowSection())),
            const SliverToBoxAdapter(child: EarlySection()),
            SliverToBoxAdapter(child: Container(key: _keys['faq'], child: const FaqSection())),
            SliverToBoxAdapter(child: Container(key: _keys['contact'], child: const SiteFooter())),
          ],
        ),
      ),
    );
  }
}
