import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/account_manager.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/google_loading.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _resolved = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final justWaiting = snapshot.connectionState == ConnectionState.waiting;

        if (justWaiting && !_resolved) {
          return Scaffold(body: const GoogleLoadingPage());
        }

        if (justWaiting && _resolved) {
          final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
          if (user != null) return const MainScreen();
          return const LoginScreen();
        }

        if (!_resolved) _resolved = true;

        if (AccountManager.instance.isSwitching) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoogleLoading(size: 32, strokeWidth: 3),
                  SizedBox(height: 16),
                  Text(
                    'Switching account...',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
