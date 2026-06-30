import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../utils/network_error.dart';
import '../../widgets/account_switcher_sheet.dart';
import '../../widgets/auth_form_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_email');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return context.tr('invalid_email');
    }
    return null;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  Future<void> _finishLogin() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified) {
      final email = user.email ?? _emailController.text.trim();
      context.go(AppRoutes.verifyEmail, extra: {'email': email});
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _saveCurrentAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'User',
        photoUrl: user.photoURL,
        provider: 'email',
        addedAt: DateTime.now(),
        isActive: true,
      ),
    );
  }

  Future<void> _saveCurrentGoogleAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'User',
        photoUrl: user.photoURL,
        provider: 'google',
        addedAt: DateTime.now(),
        isActive: true,
      ),
    );
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      await _saveCurrentAccount();
      await _finishLogin();
    } catch (e) {
      if (mounted) {
        _showError(e is NetworkError ? e.userMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().signInWithGoogle();
      await _saveCurrentGoogleAccount();
      await _finishLogin();
    } catch (e) {
      if (mounted) {
        _showError(e is NetworkError ? e.userMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        AuthPageShell(
          title: 'Soko Vibe',
          subtitle: context.tr('welcome_back'),
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(context.tr('no_account')),
              GestureDetector(
                onTap: _isLoading
                    ? null
                    : () => context.push(AppRoutes.register),
                child: Text(
                  context.tr('register'),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          child: AuthGlassCard(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  FutureBuilder<int>(
                    future: AccountManager.instance.accountCount(),
                    builder: (context, snap) {
                      if (snap.data != null && snap.data! > 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  AccountSwitcherSheet.show(context),
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 18,
                              ),
                              label: Text(context.tr('switch_account')),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: authInputDecoration(
                      context,
                      hint: context.tr('email'),
                      icon: Icons.email_outlined,
                    ),
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => login(),
                    decoration: authInputDecoration(
                      context,
                      hint: context.tr('password'),
                      icon: Icons.lock_outlined,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return context.tr('enter_password');
                      if (v.length < 8) return context.tr('password_length');
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.push(AppRoutes.forgotPassword),
                      child: Text(context.tr('forgot_password')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AuthPrimaryButton(
                    label: context.tr('login'),
                    onPressed: login,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: cs.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(context.tr('or')),
                      ),
                      Expanded(child: Divider(color: cs.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AuthGoogleButton(
                    label: context.tr('continue_google'),
                    onPressed: _isLoading ? null : signInWithGoogle,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => context.push(AppRoutes.magicLink),
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: Text('Tuma Link kwenye Barua Pepe'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AuthLoadingOverlay(visible: _isLoading),
      ],
    );
  }
}
