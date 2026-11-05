import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../theme/app_colors.dart';

class SiteNav extends StatelessWidget {
  final bool scrolled;
  final void Function(String section) onNavigate;
  final AppStrings strings;
  final VoidCallback onNotify;

  const SiteNav({
    super.key,
    required this.scrolled,
    required this.onNavigate,
    required this.strings,
    required this.onNotify,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: SokoBrand.white.withValues(alpha: scrolled ? 0.96 : 1.0),
        border: Border(bottom: BorderSide(color: SokoBrand.line.withValues(alpha: scrolled ? 1.0 : 0.0))),
        boxShadow: scrolled ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))] : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: LayoutBuilder(builder: (context, c) {
                final compact = c.maxWidth < 980;
                return Row(children: [
                  _Brand(onTap: () => onNavigate('home')),
                  if (!compact) ...[
                    const SizedBox(width: 20),
                    _NavLink(label: context.str('nav_home'), onTap: () => onNavigate('home')),
                    _NavLink(label: context.str('nav_about'), onTap: () => onNavigate('about')),
                    _NavLink(label: context.str('nav_features'), onTap: () => onNavigate('features')),
                    _NavLink(label: context.str('nav_faq'), onTap: () => onNavigate('faq')),
                    _NavLink(label: context.str('nav_contact'), onTap: () => onNavigate('contact')),
                  ],
                  const Spacer(),
                  _LangSwitch(strings: strings),
                  const SizedBox(width: 8),
                  if (!compact)
                    FilledButton(onPressed: onNotify, child: Text(context.str('nav_updates'))),
                  if (compact)
                    IconButton(
                      tooltip: context.str('nav_menu'),
                      icon: const Icon(Icons.menu),
                      onPressed: () => _openSheet(context),
                    ),
                ]);
              }),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final entry in [('home', 'nav_home'), ('about', 'nav_about'), ('features', 'nav_features'), ('faq', 'nav_faq'), ('contact', 'nav_contact')])
            ListTile(title: Text(context.str(entry.$2)), onTap: () { Navigator.pop(context); onNavigate(entry.$1); }),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () { Navigator.pop(context); onNotify(); }, child: Text(context.str('nav_updates')))),
          ),
        ]),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final VoidCallback onTap;
  const _Brand({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: SokoBrand.deepGreen, borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        const Text('Soko Vibe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: SokoBrand.ink)),
      ]),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(widget.label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _hover ? SokoBrand.deepGreen : SokoBrand.muted)),
        ),
      ),
    );
  }
}

class _LangSwitch extends StatelessWidget {
  final AppStrings strings;
  const _LangSwitch({required this.strings});
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.str('lang_label'),
      initialValue: strings.code,
      onSelected: strings.setLocale,
      itemBuilder: (_) => const [PopupMenuItem(value: 'en', child: Text('English')), PopupMenuItem(value: 'sw', child: Text('Kiswahili'))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: SokoBrand.line), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.language, size: 18, color: SokoBrand.muted), const SizedBox(width: 6), Text(strings.code.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))]),
      ),
    );
  }
}
