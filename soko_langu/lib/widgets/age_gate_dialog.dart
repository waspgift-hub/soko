import 'package:flutter/material.dart';
import '../extensions/context_tr.dart';

class AgeGateDialog extends StatelessWidget {
  final VoidCallback onConfirmed;
  final VoidCallback onDenied;

  const AgeGateDialog({
    super.key,
    required this.onConfirmed,
    required this.onDenied,
  });

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AgeGateDialog(
        onConfirmed: () => Navigator.pop(context, true),
        onDenied: () => Navigator.pop(context, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user, size: 56, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              context.tr('age_verification'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('age_gate_message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConfirmed,
                child: Text(context.tr('i_am_over_18')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onDenied,
                child: Text(context.tr('i_am_under_18')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
