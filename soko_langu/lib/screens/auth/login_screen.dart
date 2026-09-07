import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../theme/app_colors.dart';
import '../../widgets/auth/auth_scene.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/ds/ds_button.dart';

enum _LoginMethod { password, otp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  _LoginMethod _method = _LoginMethod.password;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _otpSent = false;
  bool _sendingOtp = false;
  Timer? _resendTimer;
  int _resendLeft = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
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

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendLeft = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendLeft <= 1) {
        t.cancel();
        setState(() => _resendLeft = 0);
      } else {
        setState(() => _resendLeft = _resendLeft - 1);
      }
    });
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

  Future<void> _onPasswordLogin() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().login(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
      await _saveAccount('email');
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onSendOtp() async {
    if (_sendingOtp) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError(context.tr('enter_email_please'));
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showError(context.tr('invalid_email'));
      return;
    }
    setState(() {
      _sendingOtp = true;
      _otpSent = false;
      _otpController.clear();
    });
    try {
      await context.read<AuthNotifier>().sendEmailOtp(email);
      if (!mounted) return;
      setState(() => _otpSent = true);
      _startResendCountdown();
      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _onOtpLogin() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    if (email.isEmpty || otp.length != 6) {
      _showError(context.tr('enter_otp_email_sent'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().loginWithEmailOtp(email, otp);
      await _saveAccount('otp');
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        final notifier = context.read<AuthNotifier>();
        final key = notifier.error?.toString() ?? '';
        _showError(
          key == 'auth_user_not_found' || key == 'auth_message_user_not_found'
              ? context.tr('email_not_registered', 'Akaunti haikupatikana kwa barua pepe hii. Jisajili kwanza.')
              : context.trError(e),
        );
      }
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
      leading: const _BackButton(),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.tr('no_account'), style: const TextStyle(fontSize: 13)),
          TextButton(
            onPressed: _isLoading
                ? null
                : () => context.push(AppRoutes.register),
            child: Text(
              context.tr('create_account'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      child: AuthCard(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MethodSwitcher(
                method: _method,
                onChange: (m) {
                  setState(() {
                    _method = m;
                    _otpSent = false;
                    _otpController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthTextField(
                      controller: _emailController,
                      label: context.tr('email'),
                      prefixIcon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return context.tr('enter_email_please');
                        }
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(v.trim())) {
                          return context.tr('invalid_email');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_method == _LoginMethod.password) ...[
                      AuthTextField(
                        controller: _passwordController,
                        label: context.tr('password'),
                        prefixIcon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        validator: (v) => (v == null || v.isEmpty)
                            ? context.tr('enter_password')
                            : null,
                        suffix: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        onFieldSubmitted: (_) => _onPasswordLogin(),
                      ),
                    ] else if (!_otpSent) ...[
                      DsButton(
                        label: context.tr('send_otp'),
                        icon: Icons.sms_outlined,
                        loading: _sendingOtp,
                        onPressed: _onSendOtp,
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        context.tr('enter_otp_email_sent'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _otpController,
                        label: context.tr('otp_code_hint'),
                        prefixIcon: Icons.verified_outlined,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        validator: (v) => (v == null || v.length != 6)
                            ? context.tr('enter_otp_6_digits')
                            : null,
                        onFieldSubmitted: (_) => _onOtpLogin(),
                        suffix: _resendLeft > 0
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Center(
                                  child: Text(
                                    '${_resendLeft}s',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: _sendingOtp ? null : _onSendOtp,
                                child: Text(context.tr('resend_code')),
                              ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    DsButton(
                      label: _method == _LoginMethod.password
                          ? context.tr('login')
                          : context.tr('verify'),
                      loading: _isLoading,
                      onPressed: _method == _LoginMethod.password
                          ? _onPasswordLogin
                          : _onOtpLogin,
                    ),
                    if (_method == _LoginMethod.password) ...[
                      const SizedBox(height: 4),
                      Align(
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => context.push(AppRoutes.forgotPassword),
                          child: Text(
                            context.tr('forgot_password'),
                            style: TextStyle(color: cs.primary, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      context.tr('or'),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),
              _GoogleButton(onPressed: _isLoading ? null : _onGoogleLogin),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onGoogleLogin() async {
    if (_isLoading) return;
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
}

class _MethodSwitcher extends StatelessWidget {
  final _LoginMethod method;
  final ValueChanged<_LoginMethod> onChange;

  const _MethodSwitcher({required this.method, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget option(_LoginMethod m, String label, IconData icon) {
      final selected = method == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChange(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? cs.primary : cs.brandBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(
          _LoginMethod.password,
          context.tr('login_with_email'),
          Icons.lock_outline_rounded,
        ),
        const SizedBox(width: 8),
        option(
          _LoginMethod.otp,
          context.tr('login_with_otp'),
          Icons.verified_outlined,
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

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

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _GoogleButton({this.onPressed});

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
          child: Image.network(
            // Official Google-hosted "G" — matches dark and light themes, so
            // no app asset to keep in sync with Google's branding.
            'https://www.gstatic.com/images/branding/product/2x/googleg_32dp.png',
            width: 22,
            height: 22,
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