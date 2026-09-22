import 'dart:async';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// AI + voice search demo: typed query appears, sample results fade in.
/// Clearly labeled as a demonstration illustration.
class AiSearchSection extends StatefulWidget {
  const AiSearchSection({super.key});

  @override
  State<AiSearchSection> createState() => _AiSearchSectionState();
}

class _AiSearchSectionState extends State<AiSearchSection> {
  String _typed = '';
  bool _showResults = false;
  bool _started = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _begin(String full) {
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _typed = full;
        _showResults = true;
      });
      return;
    }
    var i = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 34), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (i >= full.length) {
        t.cancel();
        setState(() => _showResults = true);
        return;
      }
      setState(() => _typed = full.substring(0, ++i));
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = context.str('ai_demo_q');
    return ResponsiveContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 88),
      child: Column(
        children: [
          AnimatedReveal(
            child: SectionHeader(
              eyebrow: context.str('ai_eyebrow'),
              title: context.str('ai_title'),
              sub: context.str('ai_sub'),
              center: true,
            ),
          ),
          const SizedBox(height: 40),
          AnimatedReveal(
            onVisible: () => _begin(query),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: SokoBrand.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: SokoBrand.line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F5F4),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search,
                              color: SokoBrand.muted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _typed.isEmpty ? '…' : _typed,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Tooltip(
                            message: context.str('ai_voice'),
                            child: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: const BoxDecoration(
                                color: SokoBrand.deepGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: _showResults
                          ? Column(
                              key: const ValueKey('results'),
                              children: [
                                const SizedBox(height: 14),
                                _DemoResult(
                                  icon: Icons.smartphone_outlined,
                                  title: 'Galaxy A15 · TSh 385,000',
                                ),
                                const SizedBox(height: 10),
                                _DemoResult(
                                  icon: Icons.smartphone_outlined,
                                  title: 'Redmi 13C · TSh 295,000',
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  context.str('ai_demo_note'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: SokoBrand.muted,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoResult extends StatelessWidget {
  final IconData icon;
  final String title;
  const _DemoResult({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: SokoBrand.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: SokoBrand.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(
            Icons.verified,
            size: 16,
            color: SokoBrand.deepGreen,
          ),
        ],
      ),
    );
  }
}

/// Delivery timeline animating in on scroll entry.
class DeliverySection extends StatefulWidget {
  const DeliverySection({super.key});

  @override
  State<DeliverySection> createState() => _DeliverySectionState();
}

class _DeliverySectionState extends State<DeliverySection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
    return Container(
      color: SokoBrand.paper,
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: ResponsiveContainer(
        child: Column(
          children: [
            AnimatedReveal(
              onVisible: () {
                if (!MediaQuery.disableAnimationsOf(context)) {
                  _controller.forward();
                } else {
                  _controller.value = 1.0;
                }
              },
              child: SectionHeader(
                eyebrow: context.str('deliver_eyebrow'),
                title: context.str('deliver_title'),
                center: true,
              ),
            ),
            const SizedBox(height: 48),
            AnimatedBuilder(
              animation: _progress,
              builder: (_, _) => ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    for (var i = 0; i < deliverySteps.length; i++) ...[
                      _TimelineRow(
                        index: i,
                        active: _progress.value * deliverySteps.length >
                            i + 0.5,
                      ),
                      if (i != deliverySteps.length - 1)
                        _TimelineLink(
                          filled: _progress.value * deliverySteps.length >
                              i + 1,
                        ),
                    ],
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

class _TimelineRow extends StatelessWidget {
  final int index;
  final bool active;
  const _TimelineRow({required this.index, required this.active});

  static const _icons = [
    Icons.shopping_bag_outlined,
    Icons.inventory_2_outlined,
    Icons.local_shipping_outlined,
    Icons.navigation_outlined,
    Icons.check_circle_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final step = deliverySteps[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? SokoBrand.black : SokoBrand.white,
            border: Border.all(
              color: active ? SokoBrand.black : SokoBrand.line,
              width: 1.5,
            ),
          ),
          child: Icon(
            _icons[index],
            size: 20,
            color: active ? Colors.white : SokoBrand.muted,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.str(step.$1),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: active ? SokoBrand.ink : SokoBrand.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.str(step.$2),
                  style: const TextStyle(
                    color: SokoBrand.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineLink extends StatelessWidget {
  final bool filled;
  const _TimelineLink({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 23),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 2,
        height: 30,
        color: filled ? SokoBrand.deepGreen : SokoBrand.line,
      ),
    );
  }
}
