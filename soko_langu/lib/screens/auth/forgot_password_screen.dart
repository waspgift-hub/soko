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

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _serverError;
  int _methodIndex = 0; // 0 = email, 1 = phone
  bool _otpSent = false;
  // ignore: unused_field
  bool _otpVerified = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
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
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) return context.tr('phone_validator_invalid');
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
    setState(() { _isLoading = true; _serverError = null; });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            content: Text(context.tr('password_reset_email_sent')),
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = context.tr('email_not_registered');
          break;
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
    if (!await RateLimiter.canProceed(action: 'forgot_password_otp', cooldown: const Duration(seconds: 45))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait before requesting another code')),
      );
      return;
    }
    setState(() { _isLoading = true; _serverError = null; });

    try {
      final normalized = _normalizePhone(_phoneController.text.trim());
      final resp = await http.post(
        Uri.parse(ApiConfig.v1('/auth/send-otp')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': normalized, 'langCode': await LocalizationService().getLanguage()}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode != 200 || result['sent'] != true) {
        setState(() => _serverError = context.tr(result['error'] ?? 'failed_to_send_otp'));
        return;
      }
      if (mounted) {
        setState(() => _otpSent = true);
        await RateLimiter.record('forgot_password_otp');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('otp_sent_to').replaceAll('{0}', _phoneController.text.trim()))),
        );
      }
    } catch (e) {
      setState(() => _serverError = context.tr('network_error_try_again'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtpAndReset() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _serverError = context.tr('password_mismatch'));
      return;
    }
    if (_newPasswordController.text.length < 8) {
      setState(() => _serverError = context.tr('password_length'));
      return;
    }
    setState(() { _isLoading = true; _serverError = null; });

    try {
      final normalized = _normalizePhone(_phoneController.text.trim());
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/reset-password-by-phone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': normalized,
          'otp': _otpController.text.trim(),
          'newPassword': _newPasswordController.text,
        }),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode != 200 || result['success'] != true) {
        setState(() => _serverError = context.tr(result['error'] ?? 'failed_to_reset_password'));
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            content: Text(context.tr('password_changed')),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _serverError = context.tr('network_error_try_again'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06), shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_reset_rounded, size: 40, color: cs.primary),
                ),
                const SizedBox(height: 20),
                Text(context.tr('reset_password'), style: TextStyle(color: cs.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(context.tr('enter_email_reset_hint'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                const SizedBox(height: 24),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(context.tr('email')), icon: Icon(Icons.email_outlined)),
                    ButtonSegment(value: 1, label: Text(context.tr('phone')), icon: Icon(Icons.phone_android)),
                  ],
                  selected: {_methodIndex},
                  onSelectionChanged: (v) => setState(() {
                    _methodIndex = v.first;
                    _serverError = null;
                    _otpSent = false;
                    _otpVerified = false;
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
                      prefixIcon: Icon(Icons.email_outlined, color: cs.onSurface.withValues(alpha: 0.59)),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
                    ),
                    validator: _emailValidator,
                  ),
                ] else ...[
                  if (!_otpSent) ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: context.tr('phone_field_hint'),
                        prefixIcon: Icon(Icons.phone_android, color: cs.onSurface.withValues(alpha: 0.59)),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
                      ),
                      validator: _phoneValidator,
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
                      decoration: InputDecoration(
                        hintText: '000000',
                        counterText: '',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      validator: Validators.password,
                      decoration: InputDecoration(
                        hintText: context.tr('new_password'),
                        prefixIcon: Icon(Icons.lock_outlined, color: cs.onSurface.withValues(alpha: 0.59)),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      validator: (v) {
                        if (v != _newPasswordController.text) {
                          return context.tr('password_mismatch');
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: context.tr('repeat_new_password'),
                        prefixIcon: Icon(Icons.lock_outlined, color: cs.onSurface.withValues(alpha: 0.59)),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
                      ),
                    ),
                  ],
                ],
                if (_serverError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_serverError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13))),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: _isLoading
                      ? const Center(child: GoogleLoading(size: 24, strokeWidth: 2))
                      : Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary]),
                          ),
                          child: ElevatedButton(
                            onPressed: _methodIndex == 0
                                ? _sendResetLink
                                : (_otpSent ? _verifyOtpAndReset : _sendPhoneOtp),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              _methodIndex == 0
                                  ? context.tr('send_reset_link')
                                  : (_otpSent ? context.tr('change_password', 'Change Password') : context.tr('send_otp')),
                              style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
