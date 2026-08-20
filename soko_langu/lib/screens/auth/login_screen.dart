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
import '../../utils/phone_utils.dart';

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
  bool _obscurePassword = true;
  bool _keepSignedIn = false;
  bool _isLoading = false;
  bool _showPhoneLogin = false;
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
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  Future<void> _finishLogin() async {
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _saveCurrentAccount(String provider) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AccountManager.instance.addOrUpdateAccount(
      SavedAccount(
        uid: user.uid,
        email: user.email ?? '',
        displayName:
            user.displayName ?? context.tr('unknown_user'),
        photoUrl: user.photoURL,
        provider: provider,
        addedAt: DateTime.now(),
        isActive: true,
      ),
    );
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context
          .read<AuthNotifier>()
          .login(_emailController.text.trim(), _passwordController.text.trim());
      await _saveCurrentAccount('email');
      await _finishLogin();
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
      await _saveCurrentAccount('google');
      await _finishLogin();
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPhoneOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final raw = _phoneController.text.trim();
    _normalizedPhone = PhoneUtils.toE164(raw);
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().sendPhoneOtp(_normalizedPhone!);
      if (mounted) {
        setState(() => _otpSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context
                  .tr('otp_sent_to')
                  .replaceAll('{0}', PhoneUtils.formatForDisplay(_normalizedPhone!)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(context.trError(e));
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
      await context
          .read<AuthNotifier>()
          .loginWithPhone(_normalizedPhone!, otp);
      await _saveCurrentAccount('phone');
      await _finishLogin();
    } catch (e) {
      if (mounted) _showError(context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration(IconData icon, {Widget? suffix}) {
    final cs = Theme.of(context).colorScheme;
    OutlineInputBorder border() => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        );
    return InputDecoration(
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: border(),
      enabledBorder: border(),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.shopping_bag,
                              color: cs.primary, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Soko Vibe',
                          style: textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Hero image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/shopping_hero.png',
                        height: 210,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 210,
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.shopping_cart,
                            size: 96,
                            color: cs.primary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Heading
                    Text(
                      'Welcome to Soko Vibe',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Log in to continue shopping',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 32),

                    if (!_showPhoneLogin) ...[
                      // Email or Phone
                      TextFormField(
                        controller: _emailController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: _inputDecoration(Icons.alternate_email)
                            .copyWith(labelText: 'Email or Phone'),
                        validator: _emailValidator,
                      ),

                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _onLogin(),
                        decoration: _inputDecoration(Icons.lock_outline,
                            suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        )).copyWith(labelText: 'Password'),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return context.tr('enter_password');
                          }
                          if (v.length < 8) return context.tr('password_length');
                          return null;
                        },
                      ),

                      const SizedBox(height: 8),

                      // Keep me signed in / Forgot password
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _keepSignedIn,
                                  onChanged: (value) => setState(
                                    () => _keepSignedIn = value ?? false,
                                  ),
                                ),
                                const Text('Keep me signed in'),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => context.push(AppRoutes.forgotPassword),
                            child: const Text('Forgot Password?'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Main action
                      SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _onLogin,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            _isLoading ? 'Logging in...' : 'Log In',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Phone + OTP login
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(Icons.phone_android)
                            .copyWith(labelText: 'Phone Number'),
                        validator: _phoneValidator,
                      ),
                      const SizedBox(height: 16),
                      if (!_otpSent)
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _sendPhoneOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              _isLoading ? 'Sending...' : 'Send OTP',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (_otpSent) ...[
                        TextFormField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                          decoration: InputDecoration(
                            hintText: '000000',
                            counterText: '',
                            filled: true,
                            fillColor:
                                cs.surfaceContainerHighest.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _loginWithPhone,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              _isLoading ? 'Verifying...' : 'Verify & Log In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: _isLoading ? null : _sendPhoneOtp,
                            child: Text(context.tr('resend_otp')),
                          ),
                        ),
                      ],
                      Center(
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() {
                                    _showPhoneLogin = false;
                                    _otpSent = false;
                                  }),
                          child: const Text('Use email & password instead'),
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Or continue with
                    Row(
                      children: [
                        Expanded(child: Divider(color: cs.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Or Continue With',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                        Expanded(child: Divider(color: cs.outlineVariant)),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Google
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _onGoogleLogin,
                        icon: Image.asset(
                          'assets/google_logo.png',
                          height: 20,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.g_mobiledata, size: 24),
                        ),
                        label: const Text(
                          'Continue with Google',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.onSurface,
                          side: BorderSide(color: cs.outlineVariant),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (!_showPhoneLogin)
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                  _showPhoneLogin = true;
                                  _otpSent = false;
                                }),
                        child: const Text('Login with Phone & OTP'),
                      )
                    else
                      const SizedBox.shrink(),

                    const SizedBox(height: 16),

                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        GestureDetector(
                          onTap: _isLoading
                              ? null
                              : () => context.push(AppRoutes.register),
                          child: Text(
                            'Sign Up',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
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
        ),
      ),
    );
  }
}