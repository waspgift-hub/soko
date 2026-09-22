import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// "Why Soko Vibe": featured escrow visual + supporting feature grid.
class WhySection extends StatelessWidget {
  const WhySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SokoBrand.paper,
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: ResponsiveContainer(
        child: Column(
          children: [
            AnimatedReveal(
              child: SectionHeader(
                eyebrow: context.str('why_eyebrow'),
                title: context.str('why_title'),
                sub: context.str('why_sub'),
                center: true,
              ),
            ),
            const SizedBox(height: 48),
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 900;
                if (compact) {
                  return const Column(
                    children: [
                      _EscrowFeature(),
                      SizedBox(height: 18),
                      _FeatureGrid(),
                    ],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _EscrowFeature()),
                    SizedBox(width: 18),
                    Expanded(flex: 7, child: _FeatureGrid()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Large featured escrow card with an animated transaction flow.
class _EscrowFeature extends StatefulWidget {
  const _EscrowFeature();

  @override
  State<_EscrowFeature> createState() => _EscrowFeatureState();
}

class _EscrowFeatureState extends State<_EscrowFeature>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const flow = ['Buyer', 'Payment', 'Escrow', 'Delivery', 'Confirm'];
    return AnimatedReveal(
      onVisible: () {
        if (!MediaQuery.disableAnimationsOf(context)) {
          _controller.forward();
        } else {
          _controller.value = 1.0;
        }
      },
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: SokoBrand.ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SokoBrand.green.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: SokoBrand.green,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    context.str('f_escrow_t'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              context.str('f_escrow_b'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _progress,
              builder: (_, _) {
                return Column(
                  children: [
                    for (var i = 0; i < flow.length; i++) ...[
                      _FlowRow(
                        label: flow[i],
                        active: _progress.value * flow.length > i,
                      ),
                      if (i != flow.length - 1)
                        _FlowLink(filled: _progress.value * flow.length > i + 0.5),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  final String label;
  final bool active;
  const _FlowRow({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? SokoBrand.green
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.5),
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _FlowLink extends StatelessWidget {
  final bool filled;
  const _FlowLink({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 2,
        height: 18,
        color:
            filled ? SokoBrand.green : Colors.white.withValues(alpha: 0.2),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('f_kyc_t', 'f_kyc_b', Icons.verified_outlined),
      ('f_chat_t', 'f_chat_b', Icons.chat_bubble_outline),
      ('f_money_t', 'f_money_b', Icons.account_balance_wallet_outlined),
      ('f_otp_t', 'f_otp_b', Icons.pin_outlined),
      ('f_ai_t', 'f_ai_b', Icons.mic_none),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final two = c.maxWidth > 480;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: two ? 2 : 1,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            mainAxisExtent: 210,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => AnimatedReveal(
            delay: Duration(milliseconds: (i % 2) * 90),
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
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SokoBrand.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      items[i].$3,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.str(items[i].$1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      context.str(items[i].$2),
                      style: const TextStyle(
                        color: SokoBrand.muted,
                        fontSize: 13,
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
    );
  }
}
