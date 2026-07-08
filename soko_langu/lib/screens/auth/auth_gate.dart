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
            if (notifier.needsProfileSetup) {
              return const ProfileSetupScreen();
            }
            return const MainScreen();
        }
      },
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
