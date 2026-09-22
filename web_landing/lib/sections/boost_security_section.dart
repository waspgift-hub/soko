import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/open_link.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// Real boost pricing (Bronze/Silver/Gold) as premium cards.
class BoostSection extends StatelessWidget {
  const BoostSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 88),
      child: Column(
        children: [
          AnimatedReveal(
            child: SectionHeader(
              eyebrow: context.str('boost_eyebrow'),
              title: context.str('boost_title'),
              sub: context.str('boost_sub'),
              center: true,
            ),
          ),
          const SizedBox(height: 44),
          LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < 760;
              final cards = [
                _PriceCard(
                  name: 'Bronze',
                  amount: 'TSh 1,500',
                  duration: context.str('boost_d3'),
                  feature: context.str('boost_bronze_f'),
                  accent: SokoBrand.bronze,
                  popular: false,
                ),
                _PriceCard(
                  name: 'Silver',
                  amount: 'TSh 3,000',
                  duration: context.str('boost_d7'),
                  feature: context.str('boost_silver_f'),
                  accent: SokoBrand.silver,
                  popular: true,
                ),
                _PriceCard(
                  name: 'Gold',
                  amount: 'TSh 10,000',
                  duration: context.str('boost_d30'),
                  feature: context.str('boost_gold_f'),
                  accent: SokoBrand.gold,
                  popular: false,
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      AnimatedReveal(child: cards[i]),
                      if (i != cards.length - 1)
                        const SizedBox(height: 16),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    Expanded(
                      child: AnimatedReveal(
                        delay: Duration(milliseconds: i * 90),
                        child: cards[i],
                      ),
                    ),
                    if (i != cards.length - 1)
                      const SizedBox(width: 18),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          AnimatedReveal(
            child: Text(
              context.str('boost_note'),
              style: const TextStyle(
                color: SokoBrand.muted,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final String name;
  final String amount;
  final String duration;
  final String feature;
  final Color accent;
  final bool popular;

  const _PriceCard({
    required this.name,
    required this.amount,
    required this.duration,
    required this.feature,
    required this.accent,
    required this.popular,
  });

  @override
  Widget build(BuildContext context) {
    final prices = Theme.of(context).extension<SokoPrices>()!;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: popular ? SokoBrand.ink : SokoBrand.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: popular ? SokoBrand.ink : SokoBrand.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: popular ? Colors.white : SokoBrand.ink,
                ),
              ),
              const Spacer(),
              if (popular)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: SokoBrand.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.str('boost_popular'),
                    style: const TextStyle(
                      color: SokoBrand.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            amount,
            style: prices.amount.copyWith(
              color: popular ? Colors.white : SokoBrand.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${context.str('boost_per')} · $duration',
            style: TextStyle(
              fontSize: 13,
              color: popular
                  ? Colors.white.withValues(alpha: 0.65)
                  : SokoBrand.muted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            feature,
            style: TextStyle(
              fontSize: 14,
              color: popular
                  ? Colors.white.withValues(alpha: 0.85)
                  : SokoBrand.ink,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    popular ? Colors.white : SokoBrand.ink,
                side: BorderSide(
                  color: popular ? Colors.white38 : SokoBrand.line,
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () =>
                  openLink(context, SokoLinks.whatsappApp),
              child: Text(context.str('boost_cta')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calm security section (no fear-based marketing).
class SecuritySection extends StatelessWidget {
  const SecuritySection({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('sec_1t', 'sec_1b', Icons.lock_outline),
      ('sec_2t', 'sec_2b', Icons.verified_outlined),
      ('sec_3t', 'sec_3b', Icons.support_agent_outlined),
      ('sec_4t', 'sec_4b', Icons.privacy_tip_outlined),
    ];
    return Container(
      color: SokoBrand.paper,
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: ResponsiveContainer(
        child: Column(
          children: [
            AnimatedReveal(
              child: SectionHeader(
                eyebrow: context.str('sec_eyebrow'),
                title: context.str('sec_title'),
                center: true,
              ),
            ),
            const SizedBox(height: 44),
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth < 600
                    ? 1
                    : c.maxWidth < 1000
                        ? 2
                        : 4;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    mainAxisExtent: 190,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => AnimatedReveal(
                    delay: Duration(milliseconds: (i % 4) * 70),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: SokoBrand.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: SokoBrand.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(items[i].$3,
                              color: SokoBrand.deepGreen),
                          const SizedBox(height: 12),
                          Text(
                            context.str(items[i].$1),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(
                              context.str(items[i].$2),
                              style: const TextStyle(
                                fontSize: 13,
                                color: SokoBrand.muted,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
