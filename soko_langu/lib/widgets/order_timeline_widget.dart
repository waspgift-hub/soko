import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class OrderTimelineStep {
  final int stepNumber;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final String label;
  final String phase;

  const OrderTimelineStep({
    required this.stepNumber,
    required this.icon,
    required this.title,
    this.description = '',
    required this.color,
    this.label = '',
    this.phase = '',
  });
}

class OrderTimelineWidget extends StatelessWidget {
  final List<OrderTimelineStep> steps;
  final int currentStep;
  final String? currentStatusLabel;
  final double? pulseValue;

  const OrderTimelineWidget({
    super.key,
    required this.steps,
    this.currentStep = 0,
    this.currentStatusLabel,
    this.pulseValue,
  });

  static const _statusColors = {
    'pending': Color(0xFF2196F3),
    'quoted': Color(0xFF00BCD4),
    'paid': Color(0xFF4CAF50),
    'escrow_hold': Color(0xFFFF9800),
    'dispatched': Color(0xFFFF5722),
    'confirmed': Color(0xFF9C27B0),
    'completed': Color(0xFFE91E63),
    'cancelled': Color(0xFFF44336),
    'disputed': Color(0xFFFFC107),
    'refunded': Color(0xFF9E9E9E),
    'failed': Color(0xFFF44336),
  };

  static Color colorForStatus(String status) =>
      _statusColors[status.toLowerCase()] ?? const Color(0xFF2196F3);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // ignore: unused_local_variable
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isLast = index == steps.length - 1;
        final isCompleted = index < currentStep;
        final isCurrent = index == currentStep;
        final stepColor = step.color;

        return IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline indicator
                SizedBox(
                  width: 56,
                  child: Column(
                    children: [
                      Container(
                        width: isCurrent ? 48 : 44,
                        height: isCurrent ? 48 : 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? stepColor
                              : isCurrent
                                  ? stepColor.withValues(alpha: 0.15)
                                  : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: Border.all(
                            color: isCompleted
                                ? stepColor
                                : isCurrent
                                    ? stepColor
                                    : cs.onSurface.withValues(alpha: 0.15),
                            width: isCurrent ? 2.5 : 1.5,
                          ),
                          boxShadow: isCurrent
                              ? [BoxShadow(color: stepColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 2))]
                              : null,
                        ),
                        child: isCompleted
                            ? const Icon(Icons.check, color: Colors.white, size: 22)
                            : Icon(step.icon,
                                color: isCurrent ? stepColor : cs.onSurface.withValues(alpha: 0.4),
                                size: isCurrent ? 22 : 20),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(
                              gradient: isCompleted
                                  ? LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [stepColor, steps[index + 1].color.withValues(alpha: 0.3)],
                                    )
                                  : LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        isCurrent ? stepColor.withValues(alpha: 0.5) : cs.onSurface.withValues(alpha: 0.08),
                                        cs.onSurface.withValues(alpha: 0.05),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Card
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: isCurrent
                          ? stepColor.withValues(alpha: 0.06)
                          : cs.surface.withValues(alpha: 0.4),
                      border: Border.all(
                        color: isCurrent
                            ? stepColor.withValues(alpha: 0.25)
                            : cs.onSurface.withValues(alpha: 0.06),
                        width: isCurrent ? 1 : 0.5,
                      ),
                      boxShadow: isCurrent
                          ? [BoxShadow(color: stepColor.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: isCurrent ? 12 : 6, sigmaY: isCurrent ? 12 : 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: isCompleted || isCurrent
                                        ? stepColor.withValues(alpha: 0.15)
                                        : cs.onSurface.withValues(alpha: 0.06),
                                  ),
                                  child: Text(
                                    step.label.isNotEmpty ? step.label : 'STEP ${step.stepNumber}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: isCompleted || isCurrent ? stepColor : cs.onSurface.withValues(alpha: 0.4),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (isCompleted)
                                  Icon(Icons.check_circle, color: stepColor, size: 18),
                                if (isCurrent && currentStatusLabel != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: stepColor.withValues(alpha: 0.15),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 10, height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: stepColor,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          currentStatusLabel!,
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: stepColor),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isCompleted || isCurrent ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
                                height: 1.2,
                              ),
                            ),
                            if (step.description.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                step.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: isCurrent ? 0.7 : 0.4),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
