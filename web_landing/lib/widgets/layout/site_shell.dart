import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import '../../router/app_router.dart';
import '../../sections/coming_soon_sections.dart' show SiteFooter;
import '../../theme/app_colors.dart';

/// Shared shell: nav + content + footer. Handles route navigation.
class SiteShell extends StatefulWidget {
  final String currentPath;
  final Widget child;
  final bool showFooter;

  const SiteShell({
    super.key,
    required this.currentPath,
    required this.child,
    this.showFooter = true,
  });

  @override
  State<SiteShell> createState() => _SiteShellState();
}

class _SiteShellState extends State<SiteShell> {
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
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

  void _navigate(String route) {
    if (route == widget.currentPath) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    Navigator.of(context).pushNamed(route);
  }

  void _goHomeWaitlist(BuildContext context) {
    if (widget.currentPath == AppRoutes.home) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      Navigator.of(
        context,
      ).pushNamed(AppRoutes.home, arguments: {'scrollTo': 'register'});
    }
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
              currentPath: widget.currentPath,
              onNavigate: _navigate,
              onWaitlist: () => _goHomeWaitlist(context),
            ),
          ),
          SliverToBoxAdapter(child: widget.child),
          if (widget.showFooter)
            SliverToBoxAdapter(child: SiteFooter(onNavigate: _navigate)),
        ],
      ),
    );
  }
}

/// Header nav using routes (shared across pages).
class SiteHeaderNav extends StatelessWidget {
  final bool scrolled;
  final AppStrings strings;
  final String currentPath;
  final void Function(String route) onNavigate;
  final VoidCallback onWaitlist;

  const SiteHeaderNav({
    super.key,
    required this.scrolled,
    required this.strings,
    required this.currentPath,
    required this.onNavigate,
    required this.onWaitlist,
  });

  static const _items = [
    (AppRoutes.home, 'nav_home'),
    (AppRoutes.about, 'nav_about'),
    (AppRoutes.howItWorks, 'nav_how'),
    (AppRoutes.features, 'nav_features'),
    (AppRoutes.buyers, 'nav_buyers'),
    (AppRoutes.sellers, 'nav_sellers'),
    (AppRoutes.faq, 'nav_faq'),
    (AppRoutes.contact, 'nav_contact'),
  ];

  void _goHomeWaitlist(BuildContext context) {
    if (currentPath == AppRoutes.home) {
      onWaitlist();
    } else {
      Navigator.of(
        context,
      ).pushNamed(AppRoutes.home, arguments: {'scrollTo': 'register'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: SokoBrand.white.withValues(alpha: scrolled ? 0.97 : 1.0),
        border: Border(
          bottom: BorderSide(
            color: SokoBrand.line.withValues(alpha: scrolled ? 1 : 0),
          ),
        ),
        boxShadow: scrolled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: LayoutBuilder(
                builder: (context, c) {
                  final compact = c.maxWidth < 1180;
                  return Row(
                    children: [
                      _Brand(onTap: () => onNavigate(AppRoutes.home)),
                      if (!compact)
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final item in _items)
                                  _NavLink(
                                    label: strings.t(item.$2),
                                    active: currentPath == item.$1,
                                    onTap: () => onNavigate(item.$1),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (compact) const Spacer(),
                      const SizedBox(width: 8),
                      _LangSwitch(strings: strings),
                      const SizedBox(width: 8),
                      if (!compact)
                        FilledButton(
                          onPressed: () => _goHomeWaitlist(context),
                          child: Text(strings.t('nav_updates')),
                        ),
                      if (compact)
                        IconButton(
                          tooltip: strings.t('nav_menu'),
                          icon: const Icon(Icons.menu),
                          onPressed: () => _openSheet(context),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in _items)
                ListTile(
                  title: Text(strings.t(item.$2)),
                  selected: currentPath == item.$1,
                  onTap: () {
                    Navigator.pop(context);
                    onNavigate(item.$1);
                  },
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _goHomeWaitlist(context);
                    },
                    child: Text(strings.t('nav_updates')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final VoidCallback onTap;
  const _Brand({required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: SokoBrand.deepGreen,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.chat_bubble_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'Soko Vibe',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: SokoBrand.ink,
          ),
        ),
      ],
    ),
  );
}

class _NavLink extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavLink({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.active || _hover
        ? SokoBrand.deepGreen
        : SokoBrand.muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            widget.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _LangSwitch extends StatelessWidget {
  final AppStrings strings;
  const _LangSwitch({required this.strings});
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: strings.t('lang_label'),
    initialValue: strings.code,
    onSelected: strings.setLocale,
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'sw', child: Text('Kiswahili')),
      PopupMenuItem(value: 'en', child: Text('English')),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: SokoBrand.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, size: 18, color: SokoBrand.muted),
          const SizedBox(width: 6),
          Text(
            strings.code.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
