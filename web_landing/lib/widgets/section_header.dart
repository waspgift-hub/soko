import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Editorial eyebrow + title + optional supporting text, layout-aware.
class SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? sub;
  final bool center;

  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.sub,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleStyle = width < 600
        ? Theme.of(context).textTheme.headlineSmall
        : Theme.of(context).textTheme.headlineLarge;
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: SokoBrand.deepGreen,
          ),
          textAlign: align,
        ),
        const SizedBox(height: 12),
        Text(title, style: titleStyle, textAlign: align),
        if (sub != null) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(sub!, style: Theme.of(context).textTheme.bodyLarge,
                textAlign: align),
          ),
        ],
      ],
    );
  }
}
