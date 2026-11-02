import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class ProfileV2Screen extends StatelessWidget {
  const ProfileV2Screen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profaili')),
      body: ListView(
        padding: const EdgeInsets.all(UiSpace.md),
        children: [
          Text(user?.displayName ?? 'Mtumiaji', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: UiSpace.xs),
          Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
          if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: UiSpace.xs),
            Text(user.phoneNumber!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: UiSpace.lg),
          UiPrimaryButton(
            label: 'Badilisha profaili',
            onPressed: () => context.push(AppRoutes.editProfile),
          ),
          const SizedBox(height: UiSpace.sm),
          UiTextAction(
            label: 'Mapendeleo ya arifa',
            onPressed: () => context.push(AppRoutes.notificationPreferences),
          ),
          UiTextAction(
            label: 'Mipangilio',
            onPressed: () => context.push(AppRoutes.settings),
          ),
          UiTextAction(
            label: 'Toka',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
      ),
    );
  }
}
