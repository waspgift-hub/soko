import 'package:flutter/material.dart';
import '../../widgets/premium_widgets.dart';

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
            Text('Set Up Your Profile', style: TextStyle(fontSize: AppFontSize.xl, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: AppInsets.md),
            Text('Complete your profile to continue', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
