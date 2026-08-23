import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_transitions.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../theme/app_colors.dart';
import '../../utils/phone_utils.dart';
import '../../widgets/auth/auth_phone_field.dart';
import '../../widgets/auth/auth_scene.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/ds/ds_button.dart';
import 'otp_screen.dart';

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

  bool _isEmailMode = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  String? _normalizedPhone;
  String? _displayPhone;
  bool _isNewUser = false;

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
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  Future<void> _saveAccount(String provider) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? context.tr('unknown_user'),
        photoUrl: user.photoURL,
        provider: provider,
        addedAt: DateTime.now(),
        isActive: true,
      ),
    );
  }

  Future<void> _onContinueWithPhone() async {
    if (!_formKey.currentState!.validate()) return;
    final raw = _phoneController.text.trim();
    _normalizedPhone = PhoneUtils.toE164WithDial(raw, '255');
    _displayPhone = _displayPhoneOf(_normalizedPhone!, '255');

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone_number', raw);

      final notifier = context.read<AuthNotifier>();
      // Branch by account existence so new users go to Sign Up instead of
      // receiving an account the server auto-created via phone-login.
      _isNewUser = !(await notifier.checkPhoneExists(_normalizedPhone!));
      await notifier.sendPhoneOtp(_normalizedPhone!);

      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).push(
        buildAppRoute(
          builder: (_) => OtpScreen(
            phone: _normalizedPhone!,
            displayPhone: _displayPhone!,
            verify: _verifyPhoneOtp,
            onSuccess: _goAfterOtp,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _displayPhoneOf(String e164, String dial) => PhoneUtils.displayWithDial(e164, dial);

  Future<String?> _verifyPhoneOtp(BuildContext ctx, String otp) async {
    final notifier = ctx.read<AuthNotifier>();
    if (_isNewUser) {
      final ok = await notifier.verifyPhoneOtp(_normalizedPhone!, otp);
      if (!ok) return ctx.tr(notifier.error ?? 'auth_otp_invalid');
      return null;
    }
    try {
      await notifier.loginWithPhone(_normalizedPhone!, otp);
      await _saveAccount('phone');
      return null;
    } catch (_) {
      return ctx.tr(notifier.error ?? 'auth_otp_invalid');
    }
  }

  void _goAfterOtp(BuildContext ctx) {
    if (!mounted) return;
    Navigator.of(ctx).pop();
    if (_isNewUser) {
      context.push(
        AppRoutes.register,
        extra: {
          'phone': _normalizedPhone,
          'displayPhone': _displayPhone,
          'otpVerified': true,
        },
      );
    } else {
      // Auth state already changed; router redirect detects
      // authenticated user on /login and navigates to home.
    }
  }

  Future<void> _onEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context
          .read<AuthNotifier>()
          .login(_emailController.text.trim(), _passwordController.text.trim());
      await _saveAccount('email');
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().signInWithGoogle();
      await _saveAccount('google');
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthScene(
      heading: context.tr('welcome_back'),
      subtitle: context.tr('login_subtitle'),
      leading: _BackButton(),
      footer: TextButton(
        onPressed: _isLoading
            ? null
            : () => context.push(AppRoutes.register),
        child: Text(
          context.tr('no_account_yet'),
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: AuthCard(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isEmailMode
              ? _EmailForm(
                  key: const ValueKey('email-form'),
                  emailController: _emailController,
                  passwordController: _passwordController,
                  formKey: _formKey,
                  obscure: _obscurePassword,
                  isLoading: _isLoading,
                  onToggleObscure: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  onLogin: _onEmailLogin,
                  onGoogleLogin: _onGoogleLogin,
                  onSwitchToPhone: () =>
                      setState(() => _isEmailMode = false),
                )
              : _PhoneForm(
                  key: const ValueKey('phone-form'),
                  formKey: _formKey,
                  phoneController: _phoneController,
                  isLoading: _isLoading,
                  onContinue: _onContinueWithPhone,
                  onGoogleLogin: _onGoogleLogin,
                  onSwitchToEmail: () => setState(() => _isEmailMode = true),
                ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    if (!canPop) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      tooltip: 'Back',
    );
  }
}

class _PhoneForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneController;
  final bool isLoading;
  final VoidCallback onContinue;
  final VoidCallback onGoogleLogin;
  final VoidCallback onSwitchToEmail;

  const _PhoneForm({
    super.key,
    required this.formKey,
    required this.phoneController,
    required this.isLoading,
    required this.onContinue,
    required this.onGoogleLogin,
    required this.onSwitchToEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPhoneField(
            controller: phoneController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onContinue(),
            validator: (v) {
              final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
              if (digits.length < 9) return context.tr('phone_validator_invalid');
              return null;
            },
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('otp_arrives_via_sms'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          DsButton(
            label: context.tr('continue'),
            onPressed: isLoading ? null : onContinue,
            loading: isLoading,
            icon: Icons.arrow_forward_rounded,
          ),
          const SizedBox(height: 6),
          _GoogleButton(onPressed: onGoogleLogin),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: isLoading ? null : onSwitchToEmail,
              child: Text(
                context.tr('login_with_email'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscure;
  final bool isLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final VoidCallback onGoogleLogin;
  final VoidCallback onSwitchToPhone;

  const _EmailForm({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscure,
    required this.isLoading,
    required this.onToggleObscure,
    required this.onLogin,
    required this.onGoogleLogin,
    required this.onSwitchToPhone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            controller: emailController,
            label: context.tr('email'),
            hint: 'you@example.com',
            prefixIcon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return context.tr('enter_email');
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                return context.tr('invalid_email');
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          AuthTextField(
            controller: passwordController,
            label: context.tr('password'),
            suffix: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              onPressed: isLoading ? null : onToggleObscure,
            ),
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => onLogin(),
            validator: (v) {
              if (v == null || v.isEmpty) return context.tr('enter_password');
              if (v.length < 8) return context.tr('password_length');
              return null;
            },
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading
                  ? null
                  : () => context.push(AppRoutes.forgotPassword),
              child: Text(
                context.tr('forgot_password'),
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DsButton(
            label: context.tr('login'),
            onPressed: isLoading ? null : onLogin,
            loading: isLoading,
            icon: Icons.login_rounded,
          ),
          const SizedBox(height: 6),
          _GoogleButton(onPressed: onGoogleLogin),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: isLoading ? null : onSwitchToPhone,
              child: Text(
                context.tr('login_with_phone'),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.brandBorder, width: 1),
      ),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: cs.surface.withValues(alpha: 0.4),
        ),
        icon: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            'assets/google_logo.jpg',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.g_mobiledata, size: 22),
          ),
        ),
        label: Text(
          context.tr('continue_google'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}