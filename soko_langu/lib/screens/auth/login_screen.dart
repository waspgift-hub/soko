import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../utils/network_error.dart';
import '../../utils/phone_utils.dart';
import '../../widgets/account_switcher_sheet.dart';
import '../../widgets/auth_form_widgets.dart';
import '../../widgets/premium_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _usePhoneLogin = false;
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
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
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

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Theme.of(context).colorScheme.error, content: Text(msg)),
    );
  }

  Future<void> _finishLogin() async {
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _saveCurrentAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(uid: user.uid, email: user.email ?? '', displayName: user.displayName ?? context.tr('unknown_user'), photoUrl: user.photoURL, provider: 'email', addedAt: DateTime.now(), isActive: true),
    );
  }

  Future<void> _saveCurrentGoogleAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(uid: user.uid, email: user.email ?? '', displayName: user.displayName ?? context.tr('unknown_user'), photoUrl: user.photoURL, provider: 'google', addedAt: DateTime.now(), isActive: true),
    );
  }

  Future<void> _saveCurrentPhoneAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(uid: user.uid, email: user.email ?? '', displayName: user.displayName ?? context.tr('unknown_user'), photoUrl: user.photoURL, provider: 'phone', addedAt: DateTime.now(), isActive: true),
    );
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().login(_emailController.text.trim(), _passwordController.text.trim());
      await _saveCurrentAccount();
      await _finishLogin();
    } catch (e) {
      if (mounted) _showError(e is NetworkError ? e.userMessage : e.toString());
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
      if (mounted) _showError(e is NetworkError ? e.userMessage : e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPhoneOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final raw = _phoneController.text.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    _normalizedPhone = digits.startsWith('0')
        ? '255${digits.substring(1)}'
        : digits.startsWith('255') ? digits : '255$digits';
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().sendPhoneOtp(_normalizedPhone!);
      if (mounted) {
        setState(() => _otpSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('otp_sent_to').replaceAll('{0}', PhoneUtils.formatForDisplay(_normalizedPhone!)))),
        );
      }
    } catch (e) {
      if (mounted) _showError(e is NetworkError ? e.userMessage : e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithPhone() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError(context.tr('otp_six_digits'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().loginWithPhone(_normalizedPhone!, otp);
      await _saveCurrentPhoneAccount();
      await _finishLogin();
    } catch (e) {
      if (mounted) _showError(e is NetworkError ? e.userMessage : e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: PremiumScaffold(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppInsets.xl),
            child: Column(
              children: [
                const SizedBox(height: 48),
                // Brand
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: Icon(Icons.store_rounded, color: cs.onPrimary, size: 36),
                ),
                const SizedBox(height: 20),
                Text(context.tr('app_name'), style: TextStyle(fontSize: AppFontSize.display, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -1)),
                const SizedBox(height: 6),
                Text(context.tr('welcome_back'), style: TextStyle(fontSize: AppFontSize.lg, color: cs.onSurfaceVariant)),
                const SizedBox(height: 32),
                // Switch account
                FutureBuilder<int>(
                  future: AccountManager.instance.accountCount(),
                  builder: (context, snap) {
                    if (snap.data != null && snap.data! > 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppInsets.lg),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => AccountSwitcherSheet.show(context),
                            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                            label: Text(context.tr('switch_account')),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                // Login tabs
                GlassCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _LoginTab(label: context.tr('login_tab_email'), selected: !_usePhoneLogin, onTap: () => setState(() { _usePhoneLogin = false; _otpSent = false; }))),
                            const SizedBox(width: AppInsets.sm),
                            Expanded(child: _LoginTab(label: context.tr('login_tab_phone'), selected: _usePhoneLogin, onTap: () => setState(() { _usePhoneLogin = true; _otpSent = false; }))),
                          ],
                        ),
                        const SizedBox(height: AppInsets.xl),
                        if (!_usePhoneLogin) ...[
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: authInputDecoration(context, hint: context.tr('email'), icon: Icons.email_outlined),
                            validator: _emailValidator,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => login(),
                            decoration: authInputDecoration(context, hint: context.tr('password'), icon: Icons.lock_outlined, suffix: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: cs.onSurface.withValues(alpha: 0.55), size: 20),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            )),
                            validator: (v) { if (v == null || v.isEmpty) return context.tr('enter_password'); if (v.length < 8) return context.tr('password_length'); return null; },
                          ),
                          Align(alignment: Alignment.centerRight, child: TextButton(
                            onPressed: _isLoading ? null : () => context.push(AppRoutes.forgotPassword),
                            child: Text(context.tr('forgot_password')),
                          )),
                          const SizedBox(height: AppInsets.sm),
                          PremiumButton(label: context.tr('login'), onPressed: login, isLoading: _isLoading),
                        ],
                        if (_usePhoneLogin) ...[
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: authInputDecoration(context, hint: context.tr('phone_field_hint'), icon: Icons.phone_android),
                            validator: _phoneValidator,
                          ),
                          const SizedBox(height: 14),
                          if (!_otpSent)
                            PremiumButton(label: context.tr('send_otp'), onPressed: _sendPhoneOtp, isLoading: _isLoading),
                          if (_otpSent) ...[
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
                              decoration: InputDecoration(
                                hintText: '000000', counterText: '', filled: true,
                                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
                              ),
                            ),
                            const SizedBox(height: AppInsets.lg),
                            PremiumButton(label: context.tr('login_with_otp'), onPressed: _loginWithPhone, isLoading: _isLoading),
                            Center(child: TextButton(
                              onPressed: _isLoading ? null : _sendPhoneOtp,
                              child: Text(context.tr('resend_otp')),
                            )),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppInsets.xl),
                Row(
                  children: [
                    Expanded(child: Divider(color: cs.outlineVariant)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: AppInsets.md), child: Text(context.tr('or'), style: TextStyle(color: cs.onSurfaceVariant))),
                    Expanded(child: Divider(color: cs.outlineVariant)),
                  ],
                ),
                const SizedBox(height: AppInsets.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : signInWithGoogle,
                    icon: Image.asset('assets/google_logo.png', height: 20, errorBuilder: (_,_,_) => const Icon(Icons.g_mobiledata, size: 24)),
                    label: Text(context.tr('continue_google')),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                if (!_usePhoneLogin) ...[
                  const SizedBox(height: AppInsets.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => context.push(AppRoutes.magicLink),
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: Text(context.tr('send_magic_link_button')),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ],
                const SizedBox(height: AppInsets.xxl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(context.tr('no_account'), style: TextStyle(color: cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: _isLoading ? null : () => context.push(AppRoutes.register),
                      child: Text(context.tr('register'), style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: AppInsets.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LoginTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppInsets.md),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 1.5 : 1),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: selected ? cs.primary : cs.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, fontSize: 14)),
        ),
      ),
    );
  }
}
