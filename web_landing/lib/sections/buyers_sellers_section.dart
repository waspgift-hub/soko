import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/open_link.dart';
import '../widgets/premium_button.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// Split buyers section: marketplace visual left, checklist right.
class BuyersSection extends StatelessWidget {
  const BuyersSection({super.key});

  @override
  Widget build(BuildContext context) {
    const points = [
      'buyers_1',
      'buyers_2',
      'buyers_3',
      'buyers_4',
      'buyers_5',
    ];
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 88),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 900;
          final list = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedReveal(
                child: SectionHeader(
                  eyebrow: context.str('buyers_eyebrow'),
                  title: context.str('buyers_title'),
                ),
              ),
              const SizedBox(height: 28),
              for (final k in points)
                AnimatedReveal(child: _CheckRow(textKey: k)),
              const SizedBox(height: 32),
              AnimatedReveal(
                child: PremiumButton(
                  label: context.str('cta_buy'),
                  icon: Icons.arrow_forward,
                  onTap: () => openLink(context, SokoLinks.whatsappBuy),
                ),
              ),
            ],
          );
          final visual = AnimatedReveal(
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: SokoBrand.paper,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: SokoBrand.line),
              ),
              child: const _BuyerVisual(),
            ),
          );
          if (compact) {
            return Column(children: [visual, const SizedBox(height: 40), list]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: visual),
              const SizedBox(width: 64),
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String textKey;
  const _CheckRow({required this.textKey});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: SokoBrand.deepGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 16,
              color: SokoBrand.deepGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              context.str(textKey),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyerVisual extends StatelessWidget {
  const _BuyerVisual();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: SokoBrand.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: SokoBrand.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: SokoBrand.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.str('hero_mock_search'),
                  style: const TextStyle(color: SokoBrand.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.mic_none, color: SokoBrand.deepGreen),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                  icon: Icons.chat_bubble_outline,
                  label: context.str('f_chat_t')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                  icon: Icons.lock_outline,
                  label: context.str('f_escrow_t')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                  icon: Icons.local_shipping_outlined,
                  label: context.str('card_delivery')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                  icon: Icons.verified_outlined,
                  label: context.str('card_verified')),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SokoBrand.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SokoBrand.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: SokoBrand.deepGreen),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sellers section: checklist + subtle animated dashboard preview.
class SellersSection extends StatelessWidget {
  const SellersSection({super.key});

  @override
  Widget build(BuildContext context) {
    const points = [
      'sellers_1',
      'sellers_2',
      'sellers_3',
      'sellers_4',
      'sellers_5',
    ];
    return Container(
      color: SokoBrand.paper,
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: ResponsiveContainer(
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 900;
            final list = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedReveal(
                  child: SectionHeader(
                    eyebrow: context.str('sellers_eyebrow'),
                    title: context.str('sellers_title'),
                    sub: context.str('sellers_sub'),
                  ),
                ),
                const SizedBox(height: 28),
                for (final k in points)
                  AnimatedReveal(child: _CheckRow(textKey: k)),
                const SizedBox(height: 32),
                AnimatedReveal(
                  child: PremiumButton(
                    label: context.str('cta_sell'),
                    icon: Icons.arrow_forward,
                    onTap: () =>
                        openLink(context, SokoLinks.whatsappSell),
                  ),
                ),
              ],
            );
            const dashboard = AnimatedReveal(child: _DashboardPreview());
            if (compact) {
              return Column(
                  children: [list, const SizedBox(height: 40), dashboard]);
            }
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _SellersList()),
                SizedBox(width: 64),
                Expanded(child: dashboard),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Extracted so the desktop Row can be const where possible.
class _SellersList extends StatelessWidget {
  const _SellersList();

  @override
  Widget build(BuildContext context) {
    const points = [
      'sellers_1',
      'sellers_2',
      'sellers_3',
      'sellers_4',
      'sellers_5',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedReveal(
          child: SectionHeader(
            eyebrow: context.str('sellers_eyebrow'),
            title: context.str('sellers_title'),
            sub: context.str('sellers_sub'),
          ),
        ),
        const SizedBox(height: 28),
        for (final k in points)
          AnimatedReveal(child: _CheckRow(textKey: k)),
        const SizedBox(height: 32),
        AnimatedReveal(
          child: PremiumButton(
            label: context.str('cta_sell'),
            icon: Icons.arrow_forward,
            onTap: () => openLink(context, SokoLinks.whatsappSell),
          ),
        ),
      ],
    );
  }
}

/// Seller dashboard preview with a subtle animated bar chart.
/// Values are neutral placeholders, explicitly labeled as a sample.
class _DashboardPreview extends StatefulWidget {
  const _DashboardPreview();

  @override
  State<_DashboardPreview> createState() => _DashboardPreviewState();
}

class _DashboardPreviewState extends State<_DashboardPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _growth;

  static const _bars = [0.35, 0.5, 0.42, 0.62, 0.55, 0.78, 0.92];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _growth = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedReveal(
      onVisible: () {
        if (!MediaQuery.disableAnimationsOf(context)) {
          _controller.forward();
        } else {
          _controller.value = 1.0;
        }
      },
      child: Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: SokoBrand.ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.str('sellers_eyebrow'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SokoBrand.green.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.str('sellers_chart'),
                    style: const TextStyle(
                      color: SokoBrand.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 150,
              child: AnimatedBuilder(
                animation: _growth,
                builder: (_, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < _bars.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: FractionallySizedBox(
                                  heightFactor:
                                      (_bars[i] * _growth.value)
                                          .clamp(0.02, 1.0),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i == _bars.length - 1
                                          ? SokoBrand.green
                                          : Colors.white
                                              .withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.str('sellers_chart_w${i + 1}'),
                                style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
