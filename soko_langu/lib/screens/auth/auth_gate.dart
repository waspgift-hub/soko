import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../notifiers/auth_notifier.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../onboarding/onboarding_screen.dart' as onboarding;
import 'login_screen.dart';
import 'profile_setup_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthNotifier>(
      builder: (context, notifier, _) {
        switch (notifier.status) {
          case AuthStatus.loading:
            return const _LoadingPage();
          case AuthStatus.onboarding:
            return const onboarding.OnboardingScreen();
          case AuthStatus.unauthenticated:
            return const LoginScreen();
          case AuthStatus.authenticated:
            if (notifier.isSuspended) return const _SuspendedPage();
            if (notifier.needsProfileSetup) {
              return const ProfileSetupScreen();
            }
            return const MainScreen();
        }
      },
    );
  }
}

class _SuspendedPage extends StatelessWidget {
  const _SuspendedPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 80, color: cs.error),
              const SizedBox(height: 24),
              Text(
                'Akaunti Yako Imesimamishwa',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Akaunti yako imesitishwa kwa muda. Tafadhali wasiliana na usaidizi kwa maelezo zaidi.',
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const GoogleLoadingPage(),
    );
  }
}
