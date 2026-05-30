import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../extensions/context_tr.dart';
import '../../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailKey = GlobalKey<FormState>();
  final _otpKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final otpController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  int _step = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  static const _serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://sokolangu-production.up.railway.app',
  );
  bool _otpSent = false;

  @override
  void dispose() {
    emailController.dispose();
    otpController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_email');
    if (!_isValidEmail(v)) return context.tr('invalid_email');
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return context.tr('enter_password');
    if (v.length < 6) return context.tr('password_length');
    return null;
  }

  Future<void> _sendOtp() async {
    if (!_emailKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_serverUrl/api/send-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': emailController.text.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['sent'] == true) {
        setState(() { _step = 1; _otpSent = true; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text(context.tr('otp_sent'))),
          );
        }
      } else {
        _showError(data['error'] ?? 'Kushindwa kutuma OTP');
      }
    } catch (e) {
      _showError('Hitilafu ya mtandao: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (!_otpKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_serverUrl/api/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': emailController.text.trim(),
              'otp': otpController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['valid'] == true) {
        setState(() => _step = 2);
      } else {
        _showError(data['error'] ?? 'OTP si sahihi');
      }
    } catch (e) {
      _showError('Hitilafu ya mtandao: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    if (passwordController.text != confirmPasswordController.text) {
      _showError(context.tr('password_mismatch'));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_serverUrl/api/reset-password-after-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': emailController.text.trim(),
              'newPassword': passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['success'] == true) {
        if (data['customToken'] != null) {
          await FirebaseAuth.instance.signInWithCustomToken(data['customToken']);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text(context.tr('password_reset_success'))),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        _showError(data['error'] ?? 'Kushindwa kuweka upya nenosiri');
      }
    } catch (e) {
      _showError('Hitilafu ya mtandao: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendFirebaseResetEmail() async {
    if (!_emailKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await AuthService().resetPassword(emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text(context.tr('password_reset_email_sent'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 32,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/soko_langu_logo.png',
                  width: 80, height: 80, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              Text(context.tr('reset_password'),
                style: TextStyle(color: cs.primary, fontSize: 26,
                  fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              const SizedBox(height: 6),
              Text(
                _step == 0 ? context.tr('enter_email')
                    : _step == 1 ? context.tr('enter_otp_step')
                    : context.tr('enter_new_password'),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 32),
              _buildStepIndicator(cs),
              const SizedBox(height: 24),
              if (_step == 0) _buildEmailStep(cs),
              if (_step == 1) _buildOtpStep(cs),
              if (_step == 2) _buildPasswordStep(cs),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr('login_prompt'),
                  style: TextStyle(color: cs.primary, fontSize: 14)),
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
      children: List.generate(3, (i) {
        final isActive = i <= _step;
        final isCurrent = i == _step;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isCurrent ? 14 : 10,
              height: isCurrent ? 14 : 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? cs.primary : cs.outlineVariant,
              ),
            ),
            if (i < 2) Container(
              width: 32, height: 2,
              color: i < _step ? cs.primary : cs.outlineVariant,
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCard({required ColorScheme cs, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.primary.withOpacity(0.5), width: 1.5),
        ),
        child: child,
      ),
    );
  }

  Widget _buildGradientButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity, height: 50,
      child: _isLoading
          ? Center(child: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Theme.of(context).colorScheme.primary),
            ))
          : Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                ),
              ),
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon, ColorScheme cs) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: cs.onSurface.withOpacity(0.6)),
      filled: true,
      fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
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
    );
  }

  Widget _buildEmailStep(ColorScheme cs) {
    return _buildCard(cs: cs, child: Column(
      children: [
        Icon(Icons.email_outlined, size: 48, color: cs.primary),
        const SizedBox(height: 16),
        Form(
          key: _emailKey,
          child: TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _inputDecoration(context.tr('email'), Icons.email_outlined, cs),
            validator: _emailValidator,
          ),
        ),
        const SizedBox(height: 20),
        _buildGradientButton(context.tr('send_otp'), _sendOtp),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(context.tr('or'),
                style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12)),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 50,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _sendFirebaseResetEmail,
            icon: const Icon(Icons.email, size: 18),
            label: Text(context.tr('send_reset_link')),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(color: cs.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    ));
  }

  Widget _buildOtpStep(ColorScheme cs) {
    return _buildCard(cs: cs, child: Column(
      children: [
        Icon(Icons.pin_outlined, size: 48, color: cs.primary),
        const SizedBox(height: 16),
        Form(
          key: _otpKey,
          child: TextFormField(
            controller: otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.bold, color: cs.primary),
            decoration: _inputDecoration('000000', Icons.pin_outlined, cs).copyWith(counterText: ''),
            validator: (v) {
              if (v == null || v.trim().length < 6) return context.tr('enter_otp_step');
              return null;
            },
          ),
        ),
        const SizedBox(height: 20),
        _buildGradientButton(context.tr('verify_otp'), _verifyOtp),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _otpSent ? _sendOtp : null,
          child: Text(context.tr('resend_otp'),
            style: TextStyle(
              color: _otpSent ? cs.primary : cs.onSurface.withOpacity(0.4),
              fontSize: 13,
            )),
        ),
      ],
    ));
  }

  Widget _buildPasswordStep(ColorScheme cs) {
    return _buildCard(cs: cs, child: Column(
      children: [
        Icon(Icons.lock_reset, size: 48, color: cs.primary),
        const SizedBox(height: 16),
        Form(
          key: _passwordKey,
          child: Column(
            children: [
              TextFormField(
                controller: passwordController,
                obscureText: _obscurePassword,
                decoration: _inputDecoration(context.tr('password'), Icons.lock_outlined, cs).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: cs.onSurface.withOpacity(0.6), size: 20),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: _passwordValidator,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: _inputDecoration(context.tr('confirm_password'), Icons.lock_outlined, cs).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: cs.onSurface.withOpacity(0.6), size: 20),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return context.tr('enter_password');
                  if (v != passwordController.text) return context.tr('password_mismatch');
                  return null;
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildGradientButton(context.tr('reset_and_login'), _resetPassword),
      ],
    ));
  }
}

