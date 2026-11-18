import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart' show AppConfig;
import '../../models/otp_verification_models.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../theme/app_colors.dart';
import '../../utils/network_error.dart';
import '../../widgets/auth/auth_scene.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/ds/ds_button.dart';

class LoginScreen extends StatefulWidget {
  final bool isRegister;
  const LoginScreen({super.key, this.isRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _sendingOtp = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
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

  Future<void> _onContinueWithEmail() async {
    if (_sendingOtp) return;
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    setState(() => _sendingOtp = true);
    try {
      await context.read<AuthNotifier>().sendEmailOtp(email);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.pushNamed(
        AppRoutes.otpVerification,
        extra: OtpVerificationRequest(
          purpose: OtpPurpose.emailLogin,
          destination: email,
          maskedDestination: _maskEmail(email),
          channel: OtpChannel.email,
          otpLength: 6,
          langCode: AppConfig.of(context).langCode,
          autoSend: false,
          onVerify: (otp) async {
            try {
              await context.read<AuthNotifier>().loginWithEmailOtp(email, otp);
              await _saveAccount('otp');
              if (mounted) context.go(AppRoutes.home);
              return const OtpVerificationResult.success();
            } catch (e) {
              return OtpVerificationResult.failure(
                errorCode: 'auth_otp_invalid',
                userMessage: context.trError(e),
              );
            }
          },
          onResend: () async {
            await context.read<AuthNotifier>().sendEmailOtp(email);
            return const OtpVerificationResult.success();
          },
          allowDestinationEdit: false,
          allowResend: true,
          headingOverride: context.tr('login_with_email'),
          subtitleOverride: context.trParams('enter_code_sent', {'0': _maskEmail(email)}),
        ),
      );
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _onGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().signInWithGoogle();
      await _saveAccount('google');
      if (mounted) context.go(AppRoutes.home);
    } on MfaSignInRequired catch (e) {
      if (!mounted) return;
      context.push(AppRoutes.mfaChallenge, extra: {'resolver': e.resolver, 'email': e.email});
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}***@${email.substring(at + 1)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthScene(
      heading: widget.isRegister ? context.tr('create_account') : context.tr('welcome_back'),
      subtitle: widget.isRegister ? context.tr('register_subtitle') : context.tr('login_subtitle'),
      leading: const _BackButton(),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            widget.isRegister ? context.tr('already_have_account') : context.tr('no_account'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          ),
          TextButton(
            onPressed: _isLoading ? null : () => context.push(widget.isRegister ? AppRoutes.login : AppRoutes.register),
            child: Text(
              widget.isRegister ? context.tr('login') : context.tr('create_account'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      child: AuthCard(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  controller: _emailController,
                  label: context.tr('email'),
                  prefixIcon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  onFieldSubmitted: (_) => _onContinueWithEmail(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return context.tr('enter_email_please');
                    }
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
                      return context.tr('invalid_email');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DsButton(
                  label: context.tr('continue_email'),
                  loading: _sendingOtp,
                  onPressed: _onContinueWithEmail,
                  height: 58,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        context.tr('or'),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                _GoogleButton(onPressed: _isLoading ? null : _onGoogle),
                const SizedBox(height: 16),
                Text(
                  context.tr('terms_privacy_notice'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
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
      tooltip: context.tr('back'),
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
      height: 58,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.brandBorder, width: 1),
      ),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: cs.surface.withValues(alpha: 0.4),
        ),
        icon: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            'https://www.gstatic.com/images/branding/product/2x/googleg_32dp.png',
            width: 22,
            height: 22,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.g_mobiledata, size: 22),
          ),
        ),
        label: Text(
          context.tr('continue_google'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      ),
    );
  }
}