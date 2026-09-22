import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/open_link.dart';

/// Sticky navigation: strengthens on scroll, collapses to a sheet on mobile.
class SiteNav extends StatelessWidget {
  final bool scrolled;
  final void Function(String section) onNavigate;
  final VoidCallback onSearch;
  final AppStrings strings;

  const SiteNav({
    super.key,
    required this.scrolled,
    required this.onNavigate,
    required this.onSearch,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: SokoBrand.white.withValues(alpha: scrolled ? 0.94 : 1.0),
        border: Border(
          bottom: BorderSide(
            color: SokoBrand.line.withValues(alpha: scrolled ? 1.0 : 0.0),
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
      child: Center(
        child: ConstrainedBox(
          // Nav spans slightly wider than the 1280 content so five links
          // plus actions fit on desktop without crowding.
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: LayoutBuilder(
              builder: (context, c) {
                // Below ~1100px the menu sheet takes over.
                final compact = c.maxWidth < 1100;
                return Row(
                  children: [
                    const _Brand(),
                    if (!compact) ...[
                      const SizedBox(width: 28),
                      Flexible(
                        child: _NavLink(
                            label: context.str('nav_soko'),
                            onTap: () => onNavigate('market')),
                      ),
                      Flexible(
                        child: _NavLink(
                            label: context.str('nav_how'),
                            onTap: () => onNavigate('how')),
                      ),
                      Flexible(
                        child: _NavLink(
                            label: context.str('nav_security'),
                            onTap: () => onNavigate('security')),
                      ),
                      Flexible(
                        child: _NavLink(
                            label: context.str('nav_sellers'),
                            onTap: () => onNavigate('sellers')),
                      ),
                      Flexible(
                        child: _NavLink(
                            label: context.str('nav_faq'),
                            onTap: () => onNavigate('faq')),
                      ),
                    ],
                    const Spacer(),
                    _LangSwitch(strings: strings, compact: compact),
                    const SizedBox(width: 4),
                    // Icon-only search: the "Soko" link already scrolls to
                    // the marketplace, so a full second button wastes space.
                    if (!compact)
                      Tooltip(
                        message: context.str('nav_search'),
                        child: IconButton(
                          onPressed: onSearch,
                          icon: const Icon(Icons.search, size: 20),
                        ),
                      ),
                    if (!compact) const SizedBox(width: 8),
                    if (!compact)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: SokoBrand.deepGreen,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () =>
                            openLink(context, SokoLinks.whatsappSell),
                        child: Text(context.str('nav_sell')),
                      ),
                    if (compact) ...[
                      IconButton(
                        tooltip: context.str('nav_menu'),
                        icon: const Icon(Icons.menu),
                        onPressed: () => _openSheet(context),
                      ),
                    ],
                  ],
                );
              },
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const [
              ('market', 'nav_soko'),
              ('how', 'nav_how'),
              ('security', 'nav_security'),
              ('sellers', 'nav_sellers'),
              ('faq', 'nav_faq'),
            ])
              ListTile(
                title: Text(context.str(entry.$2)),
                onTap: () {
                  Navigator.pop(context);
                  onNavigate(entry.$1);
                },
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: SokoBrand.deepGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    openLink(context, SokoLinks.whatsappSell);
                  },
                  child: Text(context.str('nav_sell')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Mark(),
        SizedBox(width: 10),
        Text(
          'Soko Vibe',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: SokoBrand.black,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Text(
        'S',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.onTap});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hover
                ? SokoBrand.ink.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: _hover ? SokoBrand.ink : SokoBrand.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LangSwitch extends StatelessWidget {
  final AppStrings strings;

  /// Compact mode renders a short SW/EN label so narrow bars never overflow.
  final bool compact;
  const _LangSwitch({required this.strings, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.str('lang_label'),
      child: DropdownButton<String>(
        value: strings.code,
        underline: const SizedBox(),
        icon: const Icon(Icons.language, size: 18),
        selectedItemBuilder: compact
            ? (context) => const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('SW',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('EN',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]
            : null,
        items: const [
          DropdownMenuItem(value: 'sw', child: Text('Kiswahili')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (v) {
          if (v != null) strings.setLocale(v);
        },
      ),
    );
  }
}
