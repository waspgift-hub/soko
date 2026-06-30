import 'package:flutter/material.dart';
import '../screens/auth/lock_screen.dart';
import '../services/app_lock_service.dart';

/// Full-screen PIN overlay shown when the app returns from background.
class AppLockOverlay extends StatelessWidget {
  final Widget child;

  const AppLockOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLockService.instance,
      builder: (context, _) {
        return Stack(
          children: [
            child,
            if (AppLockService.instance.isLocked)
              Positioned.fill(
                child: Material(
                  child: LockScreen(
                    onUnlock: AppLockService.instance.unlock,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
