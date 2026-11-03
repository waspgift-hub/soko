import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Scores a password on 0-4 based on length and character variety.
int passwordStrengthScore(String password) {
  if (password.isEmpty) return 0;
  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (password.contains(RegExp(r'[a-z]')) && password.contains(RegExp(r'[A-Z]'))) {
    score++;
  }
  if (password.contains(RegExp(r'[0-9]'))) score++;
  if (password.contains(RegExp(r'[^A-Za-z0-9]'))) score++;
  return score.clamp(0, 4);
}

/// Animated four-bar password strength meter with a translated label.
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = passwordStrengthScore(password);

    final (labelKey, color) = switch (score) {
      0 => ('', cs.brandBorder),
      1 => ('strength_weak', cs.error),
      2 => ('strength_fair', cs.brandWarning),
      3 => ('strength_good', cs.brandInfo),
      _ => ('strength_strong', cs.primary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final active = i < score;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 4,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: active ? color : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            labelKey.isEmpty ? '' : context.tr(labelKey),
            key: ValueKey(labelKey),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}