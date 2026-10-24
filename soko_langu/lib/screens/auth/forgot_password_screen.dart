import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../widgets/google_loading.dart';
import '../../extensions/context_tr.dart';
import '../../services/api_config.dart';
import '../../services/localization_service.dart';
import '../../app/routes.dart';
import '../../utils/rate_limiter.dart';
import '../../utils/validators.dart';
import '../../models/otp_verification_models.dart';
import '../../screens/auth/otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _serverError;
  int _methodIndex = 0; // 0 = email, 1 = phone
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_email_please');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return context.tr('invalid_email');
    }
    return null;
  }

  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('phone_validator_empty');
    if (Validators.phone(v.trim()) != null) return context.tr('phone_validator_invalid');
    return null;
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '255${digits.substring(1)}';
    if (digits.startsWith('255')) return digits;
    return '255$digits';
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    // Client-side send cooldown mirrors the phone path: no unlimited reset
    // requests from one device.
    if (!await RateLimiter.canProceed(
      action: 'forgot_password_email',
      cooldown: Duration(seconds: kOtpResendCooldownSeconds),
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('otp_cooldown'))),
        );
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _serverError = null;
    });

    Future<void> showSent() async {
      await RateLimiter.record('forgot_password_email');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            content: Text(context.tr('password_reset_email_sent')),
          ),
        );
        Navigator.pop(context);
      }
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailController.text.trim());
      await showSent();
    } on FirebaseAuthException catch (e) {
      // Anti-enumeration: an unknown address gets the SAME success answer as
      // a known one, so the screen never reveals whether an account exists.
      if (e.code == 'user-not-found') {
        await showSent();
        return;
      }
      String msg;
      switch (e.code) {
        case 'invalid-email':
          msg = context.tr('invalid_email');
          break;
        default:
          msg = context.tr('failed_to_reset_password');
      }
      setState(() => _serverError = msg);
    } catch (e) {
      setState(() => _serverError = context.tr('network_error_try_again'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPhoneOtp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _serverError = context.tr('password_mismatch'));
      return;
    }
    if (!Validators.isStrongPassword(_newPasswordController.text)) {
      setState(() => _serverError = context.tr('auth_password_weak'));
      return;
    }
    if (!await RateLimiter.canProceed(
      action: 'forgot_password_otp',
      cooldown: Duration(seconds: kOtpResendCooldownSeconds),
    )) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('otp_cooldown'))));
      return;
    }
    setState(() {
      _isLoading = true;
      _serverError = null;
    });

    final normalized = _normalizePhone(_phoneController.text.trim());
    final newPassword = _newPasswordController.text;

    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.v1('/auth/send-otp')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': normalized,
          'langCode': await LocalizationService().getLanguage(),
        }),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode != 200 || result['sent'] != true) {
        setState(() => _serverError = context.tr(result['error'] ?? 'failed_to_send_otp'));
        return;
      }
      if (mounted) {
        await RateLimiter.record('forgot_password_otp');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('otp_sent_to').replaceAll('{0}', _phoneController.text.trim()),
            ),
          ),
        );
        // Navigate to the universal OTP screen for phone password reset.
        // The onVerify callback resets the password via the backend.
        if (mounted) {
          context.pushNamed(AppRoutes.otpVerification, extra: OtpVerificationRequest(
            purpose: OtpPurpose.phoneReset,
            destination: normalized,
            maskedDestination: _maskPhone(normalized),
            channel: OtpChannel.phone,
            otpLength: 6,
            langCode: 'sw',
            onVerify: (otp) async {
              final resp2 = await http.post(
                Uri.parse(ApiConfig.v1('/auth/reset-password-by-phone')),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'phone': normalized,
                  'otp': otp,
                  'newPassword': newPassword,
                }),
              );
              final result2 = jsonDecode(resp2.body);
              if (resp2.statusCode == 200 && result2['success'] == true) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      content: Text(context.tr('password_changed')),
                    ),
                  );
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  context.go(AppRoutes.login);
                }
                return const OtpVerificationResult.success();
              } else {
                return OtpVerificationResult.failure(
                  errorCode: result2['error'] ?? 'auth_otp_invalid',
                  userMessage: context.tr(result2['error'] ?? 'failed_to_reset_password'),
                );
              }
            },
            onResend: () async {
              final resp3 = await http.post(
                Uri.parse(ApiConfig.v1('/auth/send-otp')),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'phone': normalized,
                  'langCode': await LocalizationService().getLanguage(),
                }),
              );
              return resp3.statusCode == 200
                  ? const OtpVerificationResult.success()
                  : OtpVerificationResult.failure(
                      errorCode: 'auth_otp_send_failed',
                      userMessage: context.tr('failed_to_send_otp'),
                    );
            },
            allowDestinationEdit: false,
            allowResend: true,
            headingOverride: context.tr('reset_password'),
            subtitleOverride: context.trParams(
              'enter_code_sent',
              {'0': _maskPhone(normalized)},
            ),
          ));
        }
      }
    } catch (e) {
      setState(() => _serverError = context.tr('network_error_try_again'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _maskPhone(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return e164;
    return '+255 *** *** ${digits.substring(digits.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: context.tr('back'),
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_reset_rounded, size: 40, color: cs.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  context.tr('reset_password'),
                  style: TextStyle(color: cs.primary, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('enter_email_reset_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(height: 24),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      label: Text(context.tr('email')),
                      icon: Icon(Icons.email_outlined),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text(context.tr('phone')),
                      icon: Icon(Icons.phone_android),
                    ),
                  ],
                  selected: {_methodIndex},
                  onSelectionChanged: (v) => setState(() {
                    _methodIndex = v.first;
                    _serverError = null;
                  }),
                ),
                const SizedBox(height: 24),
                if (_methodIndex == 0) ...[
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _sendResetLink(),
                    decoration: InputDecoration(
                      hintText: context.tr('enter_email'),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: cs.onSurface.withValues(alpha: 0.59),
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.primary, width: 2),
                      ),
                    ),
                    validator: _emailValidator,
                  ),
                  // New password + confirm password collected before OTP verification.
                  const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      textInputAction: TextInputAction.next,
                      validator: Validators.password,
                      decoration: InputDecoration(
                        hintText: context.tr('new_password'),
                        prefixIcon: Icon(
                          Icons.lock_outlined,
                          color: cs.onSurface.withValues(alpha: 0.59),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          tooltip: context.tr(_obscureNew ? 'show_password' : 'hide_password'),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      validator: (v) {
                        if (v != _newPasswordController.text) {
                          return context.tr('password_mismatch');
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: context.tr('repeat_new_password'),
                        prefixIcon: Icon(
                          Icons.lock_outlined,
                          color: cs.onSurface.withValues(alpha: 0.59),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          tooltip: context.tr(_obscureConfirm ? 'show_password' : 'hide_password'),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 2),
                        ),
                      ),
                    ),
                  ],
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: _isLoading
                          ? const Center(child: GoogleLoading(size: 24, strokeWidth: 2))
                          : Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.tertiary,
                                  ],
                                ),
                              ),
                              child: ElevatedButton(
                                onPressed: _methodIndex == 0
                                    ? _sendResetLink
                                    : _sendPhoneOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  _methodIndex == 0
                                      ? context.tr('send_reset_link')
                                      : context.tr('send_otp'),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.surface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
