import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_breakpoints.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/open_link.dart';
import '../widgets/premium_button.dart';
import '../widgets/responsive_container.dart';

/// Hero: marketing statement left, animated app-features overview right.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      padding: EdgeInsets.symmetric(
        horizontal: layoutOf(MediaQuery.sizeOf(context).width).isMobile
            ? 20
            : 32,
        vertical: 64,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 900;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeroCopy(),
                const SizedBox(height: 48),
                _HeroPreview(key: ValueKey(context.str('doc_title'))),
              ],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: _HeroCopy()),
              SizedBox(width: 64),
              Expanded(flex: 5, child: _HeroPreview()),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    final display = MediaQuery.sizeOf(context).width < 600
        ? Theme.of(context).textTheme.displayMedium
        : Theme.of(context).textTheme.displayLarge;
    return AnimatedReveal(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: SokoBrand.deepGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: SokoBrand.deepGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: SokoBrand.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.str('hero_badge'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SokoBrand.deepGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(context.str('hero_title_a'), style: display),
          Text(
            context.str('hero_title_b'),
            style: display?.copyWith(color: SokoBrand.deepGreen),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              context.str('hero_sub'),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: SokoBrand.muted, fontSize: 18),
            ),
          ),
          const SizedBox(height: 32),
          const _HeroActions(),
        ],
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        PremiumButton(
          label: context.str('cta_buy'),
          icon: Icons.arrow_forward,
          onTap: () => openLink(context, SokoLinks.whatsappBuy),
        ),
        PremiumButton(
          label: context.str('cta_sell'),
          primary: false,
          onTap: () => openLink(context, SokoLinks.whatsappSell),
        ),
      ],
    );
  }
}

/// Sophisticated app preview built from widgets: search bar, category chips,
/// feature rows, escrow + delivery indicators.
class _HeroPreview extends StatefulWidget {
  const _HeroPreview({super.key});

  @override
  State<_HeroPreview> createState() => _HeroPreviewState();
}

class _HeroPreviewState extends State<_HeroPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = curve;
    _scale = Tween<double>(begin: 0.98, end: 1.0).animate(curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    } else {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          decoration: BoxDecoration(
            color: SokoBrand.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: SokoBrand.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: SokoBrand.line)),
                ),
                child: Column(
                  children: [
                    _MockSearch(hint: context.str('hero_mock_search')),
                    const SizedBox(height: 12),
                    const _MockChips(),
                  ],
                ),
              ),
              _FeatureRow(
                icon: Icons.lock_outline,
                title: context.str('f_escrow_t'),
                sub: context.str('f_escrow_b'),
              ),
              _FeatureRow(
                icon: Icons.chat_bubble_outline,
                title: context.str('f_chat_t'),
                sub: context.str('f_chat_b'),
              ),
              _FeatureRow(
                icon: Icons.smart_toy_outlined,
                title: context.str('f_ai_t'),
                sub: context.str('f_ai_b'),
              ),
              Container(
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SokoBrand.deepGreen.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: SokoBrand.deepGreen.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    _StatusLine(
                      icon: Icons.lock_outline,
                      text: context.str('hero_mock_escrow'),
                    ),
                    const SizedBox(height: 8),
                    _StatusLine(
                      icon: Icons.local_shipping_outlined,
                      text: context.str('hero_mock_delivery'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockSearch extends StatefulWidget {
  final String hint;
  const _MockSearch({required this.hint});

  @override
  State<_MockSearch> createState() => _MockSearchState();
}

class _MockSearchState extends State<_MockSearch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: Builder(
          builder: (context) {
            final node = Focus.of(context);
            return GestureDetector(
              onTap: () => node.requestFocus(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F4),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _focused
                        ? SokoBrand.deepGreen
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        size: 20, color: SokoBrand.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.hint,
                        style: const TextStyle(
                          color: SokoBrand.muted,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.mic_none,
                        size: 20, color: SokoBrand.deepGreen),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MockChips extends StatelessWidget {
  const _MockChips();

  @override
  Widget build(BuildContext context) {
    const chips = ['Simu', 'Samani', 'Mavazi', 'Magari'];
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++)
          Container(
            margin: EdgeInsets.only(
                right: i == chips.length - 1 ? 0 : 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:
                  i == 0 ? SokoBrand.black : const Color(0xFFF4F5F4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              chips[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: i == 0 ? Colors.white : SokoBrand.ink,
              ),
            ),
          ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SokoBrand.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: SokoBrand.deepGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SokoBrand.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatusLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SokoBrand.deepGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SokoBrand.deepGreen,
            ),
          ),
        ),
      ],
    );
  }
}
