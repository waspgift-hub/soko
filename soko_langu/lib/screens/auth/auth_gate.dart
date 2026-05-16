import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../shared/loading_widget.dart';
import '../../extensions/context_tr.dart';
import 'login_screen.dart';
import '../onboarding/account_selection_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: LoadingWidget(message: context.tr('loading')),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<bool>(
            future: _hasProfile(snapshot.data!.uid),
            builder: (context, snap) {
              if (!snap.hasData) {
                return Scaffold(
                  body: LoadingWidget(message: context.tr('loading')),
                );
              }
              if (snap.data == true) {
                return const MainScreen();
              }
              return const AccountSelectionScreen();
            },
          );
        }
        return const LoginScreen();
      },
    );
  }

  Future<bool> _hasProfile(String uid) async {
    try {
      await UserService().autoDowngradeExpired(uid);
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists) return false;
      final tier = doc.data()?['accountTier'] as String?;
      return tier != null && tier.isNotEmpty;
    } catch (e) {
      debugPrint('AuthGate _hasProfile: $e');
      return false;
    }
  }
}
