import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

/// Quantity stepper: [-] value [+]. Never drops below [min] and never
/// exceeds [max]; reaching a bound fires [onLimit] for user feedback.
class DsQuantitySelector extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final ValueChanged<bool>? onLimit;

  const DsQuantitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 999999,
    this.onLimit,
  });

  void _step(BuildContext context, int delta) {
    final next = value + delta;
    if (next < min || next > max) {
      onLimit?.call(next < min);
      return;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(context, cs, Icons.remove, () => _step(context, -1),
            enabled: value > min),
        Container(
          constraints: const BoxConstraints(minWidth: 48),
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        _btn(context, cs, Icons.add, () => _step(context, 1),
            enabled: value < max),
      ],
    );
  }

  Widget _btn(BuildContext context, ColorScheme cs, IconData icon,
      VoidCallback onTap,
      {required bool enabled}) {
    return Material(
      color: enabled
          ? cs.primary.withValues(alpha: 0.1)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s2),
          child: Icon(icon,
              size: 18,
              color: enabled ? cs.primary : cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
