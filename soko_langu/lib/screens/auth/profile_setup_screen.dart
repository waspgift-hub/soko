import 'package:flutter/material.dart';
import '../../widgets/premium_widgets.dart';
import '../../extensions/context_tr.dart';

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PremiumScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppInsets.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(context.tr('setup_your_profile'), style: TextStyle(fontSize: AppFontSize.xl, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: AppInsets.md),
            Text(context.tr('complete_profile_to_continue'), style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
