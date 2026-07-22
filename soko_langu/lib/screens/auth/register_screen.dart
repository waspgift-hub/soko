import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../utils/network_error.dart';
import '../../utils/phone_utils.dart';
import '../../widgets/auth_form_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;
  bool _otpSent = false;

  String? _normalizedPhone;

  @override
  void initState() {
    super.initState();
    _loadSavedPhone();
  }

  Future<void> _loadSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('phone_number') ?? '';
    if (saved.isNotEmpty && _phoneController.text.isEmpty) {
      _phoneController.text = saved;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_email');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return context.tr('invalid_email');
    }
    return null;
  }

  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty)
      return context.tr('phone_validator_empty');
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return context.tr('phone_validator_invalid');
    return null;
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      _showError(context.tr('accept_terms_required'));
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError(context.tr('password_mismatch'));
      return;
    }

    final raw = _phoneController.text.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    _normalizedPhone = digits.startsWith('0')
        ? '255${digits.substring(1)}'
        : digits.startsWith('255')
        ? digits
        : '255$digits';

    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().sendPhoneOtp(_normalizedPhone!);
      if (mounted) {
        setState(() => _otpSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context
                  .tr('otp_sent_to')
                  .replaceAll(
                    '{0}',
                    PhoneUtils.formatForDisplay(_normalizedPhone!),
                  ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError(e is NetworkError ? e.userMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _register() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError(context.tr('otp_six_digits'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final notifier = context.read<AuthNotifier>();
      final ok = await notifier.verifyPhoneOtp(_normalizedPhone!, otp);
      if (!ok) {
        _showError(notifier.error ?? context.tr('otp_invalid'));
        return;
      }

      await notifier.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );

      // Store phone in Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'phone': _normalizedPhone});
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

      if (mounted) {
        context.go(AppRoutes.home);
      }
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
      await context.read<AuthNotifier>().signInWithGoogle();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await AccountManager.instance.addOrUpdateAccount(
          SavedAccount(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName ?? context.tr('unknown_user'),
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
            onPressed: _isLoading
                ? null
                : () => context.replace(AppRoutes.login),
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
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: authInputDecoration(
                      context,
                      hint: context.tr('phone_field_hint'),
                      icon: Icons.phone_android,
                    ),
                    validator: _phoneValidator,
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
                      if (v.length < 8) return context.tr('password_length');
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
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
                            : (v) => setState(() => _acceptedTerms = v ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {},
                          child: RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              children: [
                                TextSpan(text: 'I ACCEPT THE '),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => context.push(AppRoutes.privacyPolicy),
                                    child: Text(
                                      'TERMS OF SERVICE',
                                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                TextSpan(text: ' AND '),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => context.push(AppRoutes.privacyPolicy),
                                    child: Text(
                                      'PRIVACY POLICY',
                                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_otpSent)
                    AuthPrimaryButton(
                      label: context.tr('send_otp'),
                      onPressed: _sendOtp,
                      loading: _isLoading,
                    ),
                  if (_otpSent) ...[
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        hintText: '000000',
                        counterText: '',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthPrimaryButton(
                      label: context.tr('verify_otp_register'),
                      onPressed: _register,
                      loading: _isLoading,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isLoading ? null : _sendOtp,
                      child: Text(
                        context.tr('resend_otp'),
                        style: TextStyle(color: cs.primary),
                      ),
                    ),
                  ],
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
      ],
    );
  }
}
