import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../widgets/google_loading.dart';
import '../../extensions/context_tr.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _step = 1; // 1=email, 2=otp, 3=new password
  bool _isLoading = false;
  String? _serverError;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
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

  String? _otpValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_otp');
    if (v.trim().length != 6) return context.tr('otp_6_digits');
    if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) return context.tr('otp_numbers_only');
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return context.tr('enter_password_please');
    if (v.length < 6) return context.tr('password_short');
    return null;
  }

  String? _confirmValidator(String? v) {
    if (v == null || v.isEmpty) return context.tr('reenter_password');
    if (v != _passwordController.text) return context.tr('password_mismatch');
    return null;
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _serverError = null; });

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _emailController.text.trim()}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['sent'] == true) {
        setState(() => _step = 2);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              content: Text(context.tr('otp_sent_email')),
            ),
          );
        }
      } else {
        setState(() => _serverError = body['error'] ?? context.tr('failed_to_send_otp'));
      }
    } catch (e) {
      setState(() => _serverError = context.tr('network_error_try_again'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _serverError = null; });

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'otp': _otpController.text.trim(),
        }),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['valid'] == true) {
        setState(() => _step = 3);
      } else {
        setState(() => _serverError = body['error'] ?? context.tr('otp_invalid'));
      }
    } catch (e) {
      setState(() => _serverError = context.tr('network_error_try_again'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _serverError = null; });

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/reset-password-after-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'newPassword': _passwordController.text,
        }),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              content: Text(context.tr('password_reset_success_login')),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        setState(() => _serverError = body['error'] ?? context.tr('failed_to_reset_password'));
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
          onPressed: () {
            if (_step > 1) {
              setState(() { _step--; _serverError = null; });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            children: [
              _buildStepIndicator(cs),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildStepContent(cs, key: ValueKey(_step)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [1, 2, 3].map((s) {
        final active = s == _step;
        final done = s < _step;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active ? Theme.of(context).colorScheme.primary : cs.surfaceContainerHighest,
              ),
              child: Center(
                child: done
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.surface, size: 18)
                    : Text('$s', style: TextStyle(
                        color: done || active ? Theme.of(context).colorScheme.surface : cs.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      )),
              ),
            ),
            if (s < 3) Container(
              width: 40, height: 3,
              color: done ? Theme.of(context).colorScheme.primary : cs.surfaceContainerHighest,
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildStepContent(ColorScheme cs, {Key? key}) {
    return Form(
      key: _formKey,
      child: Column(
        key: key,
        children: [
          if (_step == 1) _buildStep1(cs),
          if (_step == 2) _buildStep2(cs),
          if (_step == 3) _buildStep3(cs),
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
        ],
      ),
    );
  }

  Widget _buildStep1(ColorScheme cs) {
    return Column(
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
        Text(context.tr('enter_email_otp_hint'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        const SizedBox(height: 32),
        _buildEmailField(cs),
        const SizedBox(height: 24),
        _buildActionButton(context.tr('send_otp'), _sendOtp),
      ],
    );
  }

  Widget _buildStep2(ColorScheme cs) {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.08), shape: BoxShape.circle,
          ),
          child: Icon(Icons.pin_rounded, size: 40, color: Theme.of(context).colorScheme.tertiary),
        ),
        const SizedBox(height: 20),
        Text(context.tr('enter_otp_title'), style: TextStyle(color: cs.primary, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(context.tr('check_email_otp_hint'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        const SizedBox(height: 32),
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
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
          ),
          validator: _otpValidator,
        ),
        const SizedBox(height: 24),
        _buildActionButton(context.tr('verify_otp'), _verifyOtp),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _sendOtp,
          child: Text(context.tr('resend_otp'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildStep3(ColorScheme cs) {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06), shape: BoxShape.circle,
          ),
          child: Icon(Icons.key_rounded, size: 40, color: cs.primary),
        ),
        const SizedBox(height: 20),
        Text(context.tr('new_password'), style: TextStyle(color: cs.primary, fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(context.tr('choose_new_password_hint'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        const SizedBox(height: 32),
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            hintText: context.tr('new_password_hint'),
            prefixIcon: const Icon(Icons.lock_outline),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
          ),
          validator: _passwordValidator,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            hintText: context.tr('repeat_new_password'),
            prefixIcon: const Icon(Icons.lock_outline),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.50),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outlineVariant)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.primary, width: 2)),
          ),
          validator: _confirmValidator,
        ),
        const SizedBox(height: 24),
        _buildActionButton(context.tr('reset_password'), _resetPassword),
      ],
    );
  }

  Widget _buildEmailField(ColorScheme cs) {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _sendOtp(),
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
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return SizedBox(
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
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
    );
  }
}




