import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_transitions.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../services/consent_recording_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/rate_limiter.dart';
import '../../utils/phone_utils.dart';
import '../../widgets/auth/auth_phone_field.dart';
import '../../widgets/auth/auth_scene.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/password_strength_indicator.dart';
import '../../widgets/ds/ds_button.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  /// E.164 phone to prefill (used when arriving from the login OTP flow).
  final String? initialPhone;
  /// Formatted `+255 ...` phone shown when [initialPhone] is set.
  final String? displayPhone;
  /// True when the number was already verified on the OtpScreen; creation
  /// then proceeds without re-sending an OTP.
  final bool otpVerified;

  const RegisterScreen({
    super.key,
    this.initialPhone,
    this.displayPhone,
    this.otpVerified = false,
  });

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

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  String? _normalizedPhone;
  String? _displayPhone;

  @override
  void initState() {
    super.initState();
    _normalizedPhone = widget.initialPhone;
    _displayPhone = widget.displayPhone ?? _formatPhone(widget.initialPhone);
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phoneController.text = PhoneUtils.normalizeToLocal(widget.initialPhone!);
    } else {
      _loadSavedPhone();
    }
  }

  Future<void> _loadSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('phone_number') ?? '';
    if (saved.isNotEmpty && _phoneController.text.isEmpty) {
      _phoneController.text = saved;
    }
  }

  String? _formatPhone(String? e164) {
    if (e164 == null || e164.isEmpty) return null;
    return PhoneUtils.displayWithDial(e164, '255');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  String? _phoneValidator(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return context.tr('phone_validator_invalid');
    return null;
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return context.tr('invalid_email');
    }
    return null;
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      _showError(context.tr('accept_terms_required'));
      return;
    }
    if (!widget.otpVerified) {
      if (_passwordController.text != _confirmPasswordController.text) {
        _showError(context.tr('password_mismatch'));
        return;
      }
      await _sendOtpFlow();
    } else {
      if (mounted) setState(() => _isLoading = true);
      final err = await _createAccount();
      if (mounted) {
        setState(() => _isLoading = false);
        if (err != null) _showError(err);
      }
    }
  }

  Future<void> _sendOtpFlow() async {
    if (!await RateLimiter.canProceed(action: 'register_otp', cooldown: const Duration(seconds: 45))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait before requesting another code')),
      );
      return;
    }
    final raw = _phoneController.text.trim();
    _normalizedPhone = PhoneUtils.toE164WithDial(raw, '255');
    _displayPhone = _formatPhone(_normalizedPhone);

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone_number', raw);

      final notifier = context.read<AuthNotifier>();
      if (await notifier.checkPhoneExists(_normalizedPhone!)) {
        setState(() => _isLoading = false);
        _showError(context.tr('phone_already_registered'));
        return;
      }
      final emailText = _emailController.text.trim();
      if (await notifier.checkEmailExists(emailText)) {
        setState(() => _isLoading = false);
        _showError(context.tr('email_already_registered'));
        return;
      }
      await notifier.sendPhoneOtp(_normalizedPhone!);
      if (!mounted) return;
      await RateLimiter.record('register_otp');
      Navigator.of(context).push(
        buildAppRoute(
          builder: (_) => OtpScreen(
            phone: _normalizedPhone!,
            displayPhone: _displayPhone ?? _formatPhone(_normalizedPhone)!,
            verify: _verifyForRegistration,
            onSuccess: _afterRegistrationOtp,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _verifyForRegistration(
    BuildContext ctx,
    String otp,
  ) async {
    final notifier = ctx.read<AuthNotifier>();
    final ok = await notifier.verifyPhoneOtp(_normalizedPhone!, otp);
    if (!ok) return ctx.tr(notifier.error ?? 'auth_otp_invalid');
    return null;
  }

  void _afterRegistrationOtp(BuildContext ctx) {
    Navigator.of(ctx).pop();
    _createAccount().then((err) {
      if (err != null && mounted) _showError(err);
    });
  }

  /// Creates the account for the current form state and navigates home.
  Future<String?> _createAccount() async {
    final phone = _normalizedPhone ?? widget.initialPhone;
    final emailText = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final notifier = context.read<AuthNotifier>();

    try {
      if (emailText.isNotEmpty) {
        await notifier.register(
          email: emailText,
          password: password,
          displayName: name,
        );
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && phone != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'phone': phone});
        }
      } else {
        await notifier.registerWithPhone(
          phone: phone!,
          password: password,
          displayName: name,
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await AccountManager.instance.addOrUpdateAccount(
          SavedAccount(
            uid: user.uid,
            email: user.email ?? '',
            displayName: name,
            photoUrl: user.photoURL,
            provider: emailText.isNotEmpty ? 'email' : 'phone',
            addedAt: DateTime.now(),
            isActive: true,
          ),
        );
        ConsentRecordingService.instance.recordConsent(user.uid);
      }
      if (mounted) context.go(AppRoutes.home);
      return null;
    } catch (e) {
      return context.trError(e);
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
        ConsentRecordingService.instance.recordConsent(user.uid);
      }
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
      heading: context.tr('create_your_account'),
      subtitle: context.tr('signup_subtitle'),
      leading: _BackButton(),
      footer: TextButton(
        onPressed: _isLoading
            ? null
            : () => context.go(AppRoutes.login),
        child: Text(
          context.tr('already_have_account'),
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: AuthCard(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _nameController,
                label: context.tr('full_name'),
                prefixIcon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (v) {
                  if (v == null || v.trim().length < 2) {
                    return context.tr('full_name_required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _emailController,
                label: context.tr('email_optional'),
                prefixIcon: Icons.alternate_email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: _emailValidator,
              ),
              const SizedBox(height: 14),
              if (!widget.otpVerified) ...[
                AuthPhoneField(
                  controller: _phoneController,
                  validator: _phoneValidator,
                ),
              ] else ...[
                _ReadOnlyPhone(displayPhone: _displayPhone),
              ],
              const SizedBox(height: 14),
              AuthTextField(
                controller: _passwordController,
                label: context.tr('password'),
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.isEmpty) return context.tr('enter_password');
                  if (v.length < 8) return context.tr('password_length');
                  return null;
                },
              ),
              const SizedBox(height: 8),
              if (_passwordController.text.isNotEmpty)
                PasswordStrengthIndicator(password: _passwordController.text),
              const SizedBox(height: 8),
              AuthTextField(
                controller: _confirmPasswordController,
                label: context.tr('confirm_password'),
                suffix: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                validator: (v) {
                  if (v == null || v.isEmpty) return context.tr('enter_password');
                  if (v != _passwordController.text) {
                    return context.tr('password_mismatch');
                  }
                  return null;
                },
              ),
              Text(
                context.tr('password_min_hint'),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _TermsRow(
                accepted: _acceptedTerms,
                enabled: !_isLoading,
                onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
              ),
              const SizedBox(height: 16),
              DsButton(
                label: widget.otpVerified
                    ? context.tr('register')
                    : context.tr('send_otp'),
                onPressed: _isLoading ? null : _onSubmit,
                loading: _isLoading,
                icon: widget.otpVerified
                    ? Icons.person_add_alt_1_rounded
                    : Icons.forward_to_inbox_rounded,
              ),
              if (!widget.otpVerified) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Divider(color: cs.brandBorder)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        context.tr('or'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                    Expanded(child: Divider(color: cs.brandBorder)),
                  ],
                ),
                const SizedBox(height: 16),
                _GoogleRegisterButton(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                ),
              ],
            ],
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

class _ReadOnlyPhone extends StatelessWidget {
  final String? displayPhone;

  const _ReadOnlyPhone({this.displayPhone});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.brandBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayPhone ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _TermsRow extends StatelessWidget {
  final bool accepted;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  const _TermsRow({
    required this.accepted,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Checkbox(
          value: accepted,
          activeColor: cs.primary,
          onChanged: enabled ? onChanged : null,
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              children: [
                TextSpan(text: context.tr('accept_terms_prefix', 'I ACCEPT THE ')),
                WidgetSpan(
                  child: GestureDetector(
                    onTap: enabled
                        ? () => context.push(AppRoutes.termsOfService)
                        : null,
                    child: Text(
                      context.tr('terms_of_service').toUpperCase(),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                TextSpan(text: context.tr('accept_terms_separator', ' AND ')),
                WidgetSpan(
                  child: GestureDetector(
                    onTap: enabled
                        ? () => context.push(AppRoutes.privacyPolicy)
                        : null,
                    child: Text(
                      context.tr('privacy_policy').toUpperCase(),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GoogleRegisterButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _GoogleRegisterButton({this.onPressed});

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
            // Google-hosted "G" — matches dark and light themes.
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