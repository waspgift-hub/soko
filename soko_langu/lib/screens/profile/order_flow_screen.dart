import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

class OrderFlowScreen extends StatelessWidget {
  const OrderFlowScreen({super.key});

  static const _steps = [
    _FlowStep(
      icon: Icons.shopping_cart_outlined,
      titleKey: 'flow_place_order',
      descKey: 'flow_place_order_desc',
      color: Color(0xFF4A90D9),
    ),
    _FlowStep(
      icon: Icons.receipt_long_outlined,
      titleKey: 'flow_shipping_quote',
      descKey: 'flow_shipping_quote_desc',
      color: Color(0xFF14B8A6),
    ),
    _FlowStep(
      icon: Icons.phone_android_outlined,
      titleKey: 'flow_payment',
      descKey: 'flow_payment_desc',
      color: Color(0xFF059669),
    ),
    _FlowStep(
      icon: Icons.verified_user_outlined,
      titleKey: 'flow_escrow',
      descKey: 'flow_escrow_desc',
      color: Color(0xFFD97706),
    ),
    _FlowStep(
      icon: Icons.inventory_2_outlined,
      titleKey: 'flow_dispatch',
      descKey: 'flow_dispatch_desc',
      color: Color(0xFFEA580C),
    ),
    _FlowStep(
      icon: Icons.check_circle_outlined,
      titleKey: 'flow_confirm',
      descKey: 'flow_confirm_desc',
      color: Color(0xFF7C3AED),
    ),
    _FlowStep(
      icon: Icons.emoji_events_outlined,
      titleKey: 'flow_complete',
      descKey: 'flow_complete_desc',
      color: Color(0xFFEC4899),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('how_it_works')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: _steps.length,
        itemBuilder: (context, index) {
          final step = _steps[index];
          final isLast = index == _steps.length - 1;
          return _StepCard(
            step: step,
            number: index + 1,
            isLast: isLast,
            cs: cs,
          );
        },
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final _FlowStep step;
  final int number;
  final bool isLast;
  final ColorScheme cs;

  const _StepCard({
    required this.step,
    required this.number,
    required this.isLast,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left column: number circle + connector line
          SizedBox(
            width: 64,
            child: Column(
              children: [
                // Numbered circle with icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        step.color.withValues(alpha: 0.9),
                        step.color,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: step.color.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(step.icon, color: Colors.white, size: 26),
                  ),
                ),
                // Connector line (hidden for last)
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            step.color.withValues(alpha: 0.6),
                            step.color.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right column: card content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: cs.surface.withValues(alpha: 0.6),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Step number badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: step.color.withValues(alpha: 0.15),
                        ),
                        child: Text(
                          'Step $number',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: step.color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Title
                      Text(
                        context.tr(step.titleKey),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Description
                      Text(
                        context.tr(step.descKey),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowStep {
  final IconData icon;
  final String titleKey;
  final String descKey;
  final Color color;

  const _FlowStep({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.color,
  });
}


