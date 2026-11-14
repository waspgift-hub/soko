import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../sections/coming_soon_sections.dart';
import '../theme/app_colors.dart';
import '../widgets/layout/site_shell.dart' show SiteHeaderNav;
import '../router/app_router.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scroll = ScrollController();
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
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollToArg());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final past = _scroll.hasClients && _scroll.offset > 8;
    if (past != _scrolled) setState(() => _scrolled = past);
  }

  void _maybeScrollToArg() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['scrollTo'] is String) {
      _go(args['scrollTo'] as String);
    }
  }

  void _go(String section) {
    final ctx = _keys[section]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
        alignment: 0.05,
      );
    }
  }

  void _navigate(String route) {
    if (route == AppRoutes.home) {
      _go('home');
      return;
    }
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            toolbarHeight: 72,
            backgroundColor: SokoBrand.white,
            flexibleSpace: SiteHeaderNav(
              scrolled: _scrolled,
              strings: strings,
              currentPath: AppRoutes.home,
              onNavigate: _navigate,
              onWaitlist: () => _go('register'),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              key: _keys['home'],
              child: HeroSection(
                onNotify: () => _go('register'),
                onDiscover: () => _navigate(AppRoutes.about),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              key: _keys['register'],
              child: const RegisterSection(),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(key: _keys['about'], child: const AboutSection()),
          ),
          SliverToBoxAdapter(
            child: Container(
              key: _keys['features'],
              child: const FeaturesSection(),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(key: _keys['how'], child: const HowSection()),
          ),
          const SliverToBoxAdapter(child: EarlySection()),
          SliverToBoxAdapter(
            child: Container(key: _keys['faq'], child: const FaqSection()),
          ),
          SliverToBoxAdapter(
            child: Container(
              key: _keys['contact'],
              child: SiteFooter(onNavigate: _navigate),
            ),
          ),
        ],
      ),
    );
  }
}
