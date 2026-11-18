import 'package:flutter/material.dart';

import 'login_screen.dart';

/// Registration uses the same two-method entry surface as login: the backend
/// creates the account automatically once the email OTP is verified, and
/// Google sign-in creates it on first use. No separate form is needed.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(isRegister: true);
  }
}