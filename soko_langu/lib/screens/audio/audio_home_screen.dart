import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';

class AudioHomeScreen extends StatelessWidget {
  const AudioHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.go(AppRoutes.audioList);
      }
    });

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: CircularProgressIndicator(color: cs.primary),
      ),
    );
  }
}
