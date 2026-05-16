import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/auth_service.dart';
import '../../app/routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final email = TextEditingController();
  final password = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_email');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return context.tr('invalid_email');
    }
    return null;
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final cred = await _authService.login(email.text.trim(), password.text.trim());
      final user = cred.user;
      if (user != null && !user.emailVerified) {
        await user.reload();
        if (!user.emailVerified) {
          if (mounted) {
            showError(context.tr('verify_email_first'));
            context.push(AppRoutes.verifyEmail,
              extra: {'email': email.text.trim()});
          }
          return;
        }
      }
    } catch (e) {
      if (mounted) showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInWithGoogle();
    } catch (e) {
      if (mounted) showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
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
                      width: 90, height: 90, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 16),
                  Text("Soko Langu",
                    style: TextStyle(color: cs.primary, fontSize: 30,
                      fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  Text(context.tr('welcome_back'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
                  const SizedBox(height: 32),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  hintText: context.tr('email'),
                                  prefixIcon: Icon(Icons.email_outlined, color: cs.onSurface.withValues(alpha: 0.6)),
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: password,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  hintText: context.tr('password'),
                                  prefixIcon: Icon(Icons.lock_outlined, color: cs.onSurface.withValues(alpha: 0.6)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: cs.onSurface.withValues(alpha: 0.6), size: 20,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                                validator: (v) {
                                  if (v == null || v.isEmpty) return context.tr('enter_password');
                                  if (v.length < 6) return context.tr('password_length');
                                  return null;
                                },
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => context.push(AppRoutes.forgotPassword),
                                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                                  child: Text(context.tr('forgot_password'), style: const TextStyle(fontSize: 13)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: double.infinity, height: 50,
                                child: _isLoading
                                    ? Center(child: SizedBox(
                                        width: 24, height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
                                      ))
                                    : Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                                          ),
                                        ),
                                        child: ElevatedButton(
                                          onPressed: login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          ),
                                          child: Text(context.tr('login'),
                                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(context.tr('or'),
                          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                      ),
                      Expanded(child: Divider(color: cs.outlineVariant, thickness: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: _isLoading
                        ? const SizedBox.shrink()
                        : OutlinedButton.icon(
                            onPressed: signInWithGoogle,
                            icon: Container(
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Center(
                                child: Text('G',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ),
                            label: Text(context.tr('continue_google'),
                              style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w500)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: cs.outlineVariant),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              backgroundColor: cs.surface,
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(context.tr('no_account'),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => context.push(AppRoutes.register),
                        child: Text(context.tr('register'),
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
