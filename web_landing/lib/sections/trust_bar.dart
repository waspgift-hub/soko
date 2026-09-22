import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/responsive_container.dart';

/// Trust line + text-based payment chips (no invented logos).
class TrustBar extends StatelessWidget {
  const TrustBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: SokoBrand.line),
        ),
        color: SokoBrand.paper,
      ),
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: ResponsiveContainer(
        child: AnimatedReveal(
          child: Column(
            children: [
              Text(
                context.str('trust_line'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SokoBrand.muted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in paymentMethods)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: SokoBrand.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: SokoBrand.line),
                      ),
                      child: Text(
                        m,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
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
