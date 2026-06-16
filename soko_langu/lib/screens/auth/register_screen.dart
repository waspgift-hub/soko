import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../utils/network_error.dart';
import '../../widgets/auth_form_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(backgroundColor: Theme.of(context).colorScheme.error, content: Text(msg)));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(backgroundColor: Theme.of(context).colorScheme.primary, content: Text(msg)));
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      _showError(context.tr('accept_terms_required'));
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError(context.tr('password_mismatch'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.registerWithProfile(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
      try {
        await _authService.sendEmailVerification();
      } catch (_) {}

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await AccountManager.instance.addOrUpdateAccount(
          SavedAccount(
            uid: user.uid,
            email: user.email ?? '',
            displayName: _nameController.text.trim(),
            photoUrl: user.photoURL,
            provider: 'email',
            addedAt: DateTime.now(),
            isActive: true,
          ),
        );
      }

      if (!mounted) return;
      _showSuccess(context.tr('email_verification_sent'));
      context.go(AppRoutes.accountSelection);
    } catch (e) {
      if (mounted) {
        _showError(e is NetworkError ? e.userMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInWithGoogle();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
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
      if (mounted) context.go(AppRoutes.home);
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
          title: context.tr('register'),
          subtitle: context.tr('create_account'),
          footer: TextButton(
            onPressed: _isLoading ? null : () => context.pop(),
            child: Text(context.tr('login_prompt')),
          ),
          child: AuthGlassCard(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: authInputDecoration(
                      context,
                      hint: context.tr('full_name'),
                      icon: Icons.person_outline,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 2) {
                        return context.tr('full_name_required');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
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
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
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
                      if (v.length < 6) return context.tr('password_length');
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _register(),
                    decoration: authInputDecoration(
                      context,
                      hint: context.tr('confirm_password'),
                      icon: Icons.lock_outlined,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return context.tr('enter_password');
                      if (v != _passwordController.text) {
                        return context.tr('password_mismatch');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        activeColor: cs.primary,
                        onChanged: _isLoading
                            ? null
                            : (v) =>
                                  setState(() => _acceptedTerms = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          context.tr('accept_terms'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AuthPrimaryButton(
                    label: context.tr('register'),
                    onPressed: _register,
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
                    onPressed: _isLoading ? null : _signInWithGoogle,
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
