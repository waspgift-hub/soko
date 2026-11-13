import 'package:flutter/material.dart';

import '../tokens.dart';

/// The single primary action for a screen. Use [onPressed] null to disable.
class UiPrimaryButton extends StatelessWidget {
  const UiPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: UiColors.onAccent),
            )
          : Text(label),
    );
  }
}

/// Lightweight text action for secondary navigation inside a screen.
class UiTextAction extends StatelessWidget {
  const UiTextAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: onPressed, child: Text(label));
  }
}
