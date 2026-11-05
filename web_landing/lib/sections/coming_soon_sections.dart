import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../services/launch_api.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/open_link.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

class HeroSection extends StatelessWidget {
  final VoidCallback onNotify;
  final VoidCallback onDiscover;
  const HeroSection({super.key, required this.onNotify, required this.onDiscover});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final titleStyle = (w < 700 ? Theme.of(context).textTheme.displayMedium : Theme.of(context).textTheme.displayLarge)
        ?.copyWith(color: Colors.white, height: 1.05);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B141A), SokoBrand.deepGreen, SokoBrand.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ResponsiveContainer(
        padding: EdgeInsets.fromLTRB(24, w < 700 ? 56 : 88, 24, w < 700 ? 56 : 88),
        child: AnimatedReveal(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: SokoBrand.green, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(context.str('badge_under_dev'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.1)),
                ]),
              ),
              const SizedBox(height: 22),
              Text(context.str('hero_title'), style: titleStyle),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Text(context.str('hero_sub'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.88), fontSize: 18)),
              ),
              const SizedBox(height: 28),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SokoBrand.green, foregroundColor: SokoBrand.ink),
                  onPressed: onNotify,
                  child: Text(context.str('cta_notify')),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.35))),
                  onPressed: onDiscover,
                  child: Text(context.str('cta_discover')),
                ),
              ]),
              const SizedBox(height: 16),
              Text(context.str('hero_note'), style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

class RegisterSection extends StatefulWidget {
  const RegisterSection({super.key});
  @override
  State<RegisterSection> createState() => _RegisterSectionState();
}

class _RegisterSectionState extends State<RegisterSection> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _api = LaunchApi();
  late final int _startedAt;
  bool _loading = false;
  bool _success = false;
  bool _duplicate = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _message = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final lang = Localizations.localeOf(context).languageCode;
    final result = await _api.subscribe(email: _email.text, name: _name.text, lang: lang, formStartedAt: _startedAt);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = result.ok;
      _duplicate = result.duplicate;
      _message = result.ok
          ? (result.duplicate ? context.str('form_duplicate') : null)
          : (result.message.isNotEmpty ? result.message : context.str('form_error'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      color: SokoBrand.paper,
      child: ResponsiveContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
        child: AnimatedReveal(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 20 : 28),
                  child: _success ? _SuccessState(duplicate: _duplicate) : _buildForm(compact),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool compact) {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: context.str('form_eyebrow'), title: context.str('form_title'), sub: context.str('form_sub')),
        const SizedBox(height: 22),
        if (compact) ...[
          TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: context.str('form_name'))),
          const SizedBox(height: 12),
          _emailField(),
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: context.str('form_name')))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: _emailField()),
          ]),
        const SizedBox(height: 14),
        Semantics(
          label: 'Leave this field empty',
          child: const Offstage(offstage: true, child: TextField(decoration: InputDecoration(hintText: 'Website'))),
        ),
        SizedBox(
          width: compact ? double.infinity : null,
          child: FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(_loading ? context.str('form_loading') : context.str('form_submit')),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: const TextStyle(color: SokoBrand.error, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 12),
        Text(context.str('form_privacy'), style: const TextStyle(color: SokoBrand.muted, fontSize: 13, height: 1.5)),
      ]),
    );
  }

  Widget _emailField() {
    return TextFormField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      decoration: InputDecoration(labelText: context.str('form_email'), prefixIcon: const Icon(Icons.mail_outline)),
      validator: (v) {
        final value = (v ?? '').trim();
        if (value.isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(value)) {
          return context.str('form_invalid');
        }
        return null;
      },
    );
  }
}

class _SuccessState extends StatelessWidget {
  final bool duplicate;
  const _SuccessState({required this.duplicate});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: SokoBrand.deepGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.check_circle, color: SokoBrand.deepGreen, size: 30),
      ),
      const SizedBox(height: 16),
      Text(duplicate ? context.str('form_duplicate') : context.str('form_success'), style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(duplicate ? context.str('form_success_sub') : context.str('form_success_sub'), style: const TextStyle(color: SokoBrand.muted, height: 1.6)),
    ]);
  }
}

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});
  static const _cards = [('f1_t', 'f1_b', Icons.storefront_outlined), ('f2_t', 'f2_b', Icons.forum_outlined), ('f3_t', 'f3_b', Icons.groups_outlined), ('f4_t', 'f4_b', Icons.phone_iphone_outlined), ('f5_t', 'f5_b', Icons.auto_awesome_outlined), ('f6_t', 'f6_b', Icons.public_outlined)];

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedReveal(child: SectionHeader(eyebrow: context.str('about_eyebrow'), title: context.str('about_title'), sub: context.str('about_body'))),
        const SizedBox(height: 14),
        AnimatedReveal(child: Text(context.str('about_note'), style: TextStyle(color: SokoBrand.warning.withValues(alpha: 0.95), fontWeight: FontWeight.w600, fontSize: 13))),
        const SizedBox(height: 28),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 980 ? 3 : c.maxWidth >= 620 ? 2 : 1;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _cards.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 16, mainAxisSpacing: 16, mainAxisExtent: 170),
            itemBuilder: (_, i) => AnimatedReveal(
              delay: Duration(milliseconds: 60 * i),
              child: _InfoCard(title: context.str(_cards[i].$1), body: context.str(_cards[i].$2), icon: _cards[i].$3),
            ),
          );
        }),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  const _InfoCard({required this.title, required this.body, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: SokoBrand.deepGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: SokoBrand.deepGreen)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: SokoBrand.ink)),
          const SizedBox(height: 6),
          Expanded(child: Text(body, style: const TextStyle(color: SokoBrand.muted, height: 1.5, fontSize: 14))),
        ]),
      ),
    );
  }
}

class HowSection extends StatelessWidget {
  const HowSection({super.key});
  @override
  Widget build(BuildContext context) {
    const steps = [('1', 'how_1_t', 'how_1_b'), ('2', 'how_2_t', 'how_2_b'), ('3', 'how_3_t', 'how_3_b')];
    return Container(
      color: SokoBrand.white,
      child: ResponsiveContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedReveal(child: SectionHeader(eyebrow: context.str('how_eyebrow'), title: context.str('how_title'))),
          const SizedBox(height: 28),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 860 ? 3 : 1;
            return GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: steps.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 16, mainAxisSpacing: 16, mainAxisExtent: 160),
              itemBuilder: (_, i) => AnimatedReveal(
                delay: Duration(milliseconds: 80 * i),
                child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(radius: 16, backgroundColor: SokoBrand.deepGreen, child: Text(steps[i].$1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  const SizedBox(height: 14),
                  Text(context.str(steps[i].$2), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 6),
                  Text(context.str(steps[i].$3), style: const TextStyle(color: SokoBrand.muted, height: 1.5)),
                ]))),
              ),
            );
          }),
          const SizedBox(height: 14),
          Text(context.str('how_note'), style: const TextStyle(color: SokoBrand.muted, fontSize: 13)),
        ]),
      ),
    );
  }
}

class EarlySection extends StatelessWidget {
  const EarlySection({super.key});
  @override
  Widget build(BuildContext context) {
    const items = [('early_1_t', 'early_1_b', Icons.campaign_outlined), ('early_2_t', 'early_2_b', Icons.new_releases_outlined), ('early_3_t', 'early_3_b', Icons.route_outlined), ('early_4_t', 'early_4_b', Icons.diversity_3_outlined)];
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedReveal(child: SectionHeader(eyebrow: context.str('early_eyebrow'), title: context.str('early_title'))),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 980 ? 4 : c.maxWidth >= 620 ? 2 : 1;
          return GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 14, mainAxisSpacing: 14, mainAxisExtent: 175),
            itemBuilder: (_, i) => AnimatedReveal(delay: Duration(milliseconds: 50 * i), child: _InfoCard(title: context.str(items[i].$1), body: context.str(items[i].$2), icon: items[i].$3)),
          );
        }),
      ]),
    );
  }
}

class FaqSection extends StatelessWidget {
  const FaqSection({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: SokoBrand.white,
      child: ResponsiveContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedReveal(child: SectionHeader(eyebrow: context.str('faq_eyebrow'), title: context.str('faq_title'))),
            const SizedBox(height: 20),
            for (final item in faqItems)
              AnimatedReveal(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      title: Text(context.str(item.qKey), style: const TextStyle(fontWeight: FontWeight.w700, color: SokoBrand.ink)),
                      children: [Align(alignment: Alignment.centerLeft, child: Text(context.str(item.aKey), style: const TextStyle(color: SokoBrand.muted, height: 1.6)))],
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: SokoBrand.ink,
      child: ResponsiveContainer(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, c) {
            final compact = c.maxWidth < 760;
            final brand = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 38, height: 38, decoration: BoxDecoration(color: SokoBrand.deepGreen, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                const Text('Soko Vibe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
              ]),
              const SizedBox(height: 12),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(context.str('foot_desc'), style: TextStyle(color: Colors.white.withValues(alpha: 0.72), height: 1.6))),
              const SizedBox(height: 8),
              Text(context.str('foot_tag'), style: TextStyle(color: SokoBrand.green.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 13)),
            ]);
            final contact = _FooterCol(title: context.str('foot_contact'), children: [
              _FooterLink(label: SokoLinks.emailAddress, onTap: () => openLink(context, SokoLinks.email), icon: Icons.mail_outline),
            ]);
            final links = _FooterCol(title: context.str('foot_links'), children: [
              _FooterLink(label: context.str('foot_privacy'), onTap: () => openLink(context, SokoLinks.privacy)),
              _FooterLink(label: context.str('foot_terms'), onTap: () => openLink(context, SokoLinks.terms)),
            ]);
            if (compact) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [brand, const SizedBox(height: 28), contact, const SizedBox(height: 20), links]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: brand), const SizedBox(width: 24), Expanded(child: contact), Expanded(child: links)]);
          }),
          const SizedBox(height: 28),
          Divider(color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          Text(context.str('foot_rights'), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
        ]),
      ),
    );
  }
}

class _FooterCol extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _FooterCol({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    const SizedBox(height: 12),
    ...children,
  ]);
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  const _FooterLink({required this.label, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.72)), const SizedBox(width: 8)],
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.78))),
      ]),
    ),
  );
}
