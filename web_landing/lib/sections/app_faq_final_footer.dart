import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/open_link.dart';
import '../widgets/phone_mockup.dart';
import '../widgets/premium_button.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// App download showcase with device mockup (no fake store links).
class AppSection extends StatelessWidget {
  const AppSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 88),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 900;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedReveal(
                child: SectionHeader(
                  eyebrow: context.str('app_eyebrow'),
                  title: context.str('app_title'),
                  sub: context.str('app_sub'),
                ),
              ),
              const SizedBox(height: 30),
              AnimatedReveal(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    PremiumButton(
                      label: context.str('app_cta'),
                      icon: Icons.chat_outlined,
                      onTap: () =>
                          openLink(context, SokoLinks.whatsappApp),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              AnimatedReveal(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: SokoBrand.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_arrow_outlined,
                        color: SokoBrand.muted,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          context.str('app_store_note'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: SokoBrand.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          final phone = AnimatedReveal(
            child: Center(
              child: PhoneMockup(
                searchHint: context.str('hero_mock_search'),
                chips: const ['Simu', 'Samani', 'Mavazi', 'Magari'],
                rows: [
                  (Icons.lock_outline, context.str('f_escrow_t')),
                  (Icons.chat_bubble_outline, context.str('f_chat_t')),
                  (Icons.fingerprint, context.str('f_otp_t')),
                  (Icons.smart_toy_outlined, context.str('f_ai_t')),
                ],
              ),
            ),
          );
          if (compact) {
            return Column(children: [copy, const SizedBox(height: 48), phone]);
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 64),
              Expanded(child: phone),
            ],
          );
        },
      ),
    );
  }
}

/// Premium FAQ accordion (real questions only).
class FaqSection extends StatelessWidget {
  const FaqSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SokoBrand.paper,
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: ResponsiveContainer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              AnimatedReveal(
                child: SectionHeader(
                  eyebrow: context.str('faq_eyebrow'),
                  title: context.str('faq_title'),
                  center: true,
                ),
              ),
              const SizedBox(height: 40),
              for (var i = 0; i < faqItems.length; i++)
                AnimatedReveal(
                  delay: Duration(milliseconds: i * 40),
                  child: _FaqTile(item: faqItems[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final FaqItem item;
  const _FaqTile({required this.item});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile>
    with SingleTickerProviderStateMixin {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: SokoBrand.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _open ? SokoBrand.ink : SokoBrand.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.str(widget.item.qKey),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more,
                      color: SokoBrand.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.str(widget.item.aKey),
                        style: const TextStyle(
                          color: SokoBrand.muted,
                          height: 1.6,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}

/// Dramatic but clean closing CTA (green accent, not a green wall).
class FinalCtaSection extends StatelessWidget {
  final VoidCallback onServices;
  const FinalCtaSection({super.key, required this.onServices});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SokoBrand.ink,
      padding: const EdgeInsets.symmetric(vertical: 96),
      child: ResponsiveContainer(
        child: AnimatedReveal(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(
                  color: SokoBrand.green,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Text(
                  context.str('final_title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.str('final_sub'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 36),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 14,
                children: [
                  PremiumButton(
                    label: context.str('final_cta'),
                    icon: Icons.arrow_forward,
                    onTap: () =>
                        openLink(context, SokoLinks.whatsappApp),
                  ),
                  _GhostButton(
                    label: context.str('cta_services'),
                    onTap: onServices,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
            ),
            color: _hover
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Enterprise footer with real contact info only.
class SiteFooter extends StatelessWidget {
  final void Function(String section) onNavigate;
  const SiteFooter({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SokoBrand.line)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 56, 0, 28),
      child: ResponsiveContainer(
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth < 640
                    ? 1
                    : c.maxWidth < 1000
                        ? 2
                        : 4;
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 32,
                    mainAxisSpacing: 32,
                    mainAxisExtent: 250,
                  ),
                  children: [
                    _FootCol(
                      title: 'Soko Vibe',
                      links: const [],
                      tag: context.str('foot_tag'),
                    ),
                    _FootCol(
                      title: context.str('foot_soko'),
                      links: [
                        (context.str('foot_how'), () => onNavigate('how')),
                        (context.str('foot_safety'), () => onNavigate('security')),
                        (context.str('foot_fees'), () => onNavigate('boost')),
                        (context.str('foot_faq'), () => onNavigate('faq')),
                      ],
                    ),
                    _FootCol(
                      title: context.str('foot_sellers'),
                      links: [
                        (context.str('foot_sell'), null),
                        (context.str('foot_tools'), null),
                        (context.str('foot_boost'), null),
                        (context.str('foot_verify'), null),
                      ],
                      linkUrl: SokoLinks.whatsappSell,
                    ),
                    _FootCol(
                      title: context.str('foot_contact'),
                      links: const [],
                      email: true,
                    ),
                  ],
                );
              },
            ),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '© ${DateTime.now().year} Soko Vibe Limited · Dar es Salaam, Tanzania. ${context.str('foot_rights')}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SokoBrand.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FootCol extends StatelessWidget {
  final String title;
  final List<(String, VoidCallback?)> links;
  final String? tag;
  final bool email;
  final String? linkUrl;

  const _FootCol({
    required this.title,
    required this.links,
    this.tag,
    this.email = false,
    this.linkUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: SokoBrand.muted,
          ),
        ),
        const SizedBox(height: 16),
        if (tag != null)
          Text(tag!, style: const TextStyle(height: 1.6)),
        if (email) ...[
          InkWell(
            onTap: () => openLink(context, SokoLinks.email),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Text('support@sokovibe.co.tz'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 5),
            child: Text('+255 693 273 241'),
          ),
        ],
        for (final link in links)
          InkWell(
            onTap: link.$2 ??
                (linkUrl != null
                    ? () => openLink(context, linkUrl!)
                    : null),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(link.$1),
            ),
          ),
      ],
    );
  }
}
