import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiLoginScreen extends StatefulWidget {
  const OneUiLoginScreen({super.key});

  @override
  State<OneUiLoginScreen> createState() => _OneUiLoginScreenState();
}

class _OneUiLoginScreenState extends State<OneUiLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(OneUiSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: OneUiSpacing.xxl),
              // Logo
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: OneUiColors.accent,
                    borderRadius: BorderRadius.circular(OneUiRadius.lg),
                  ),
                  child: const Icon(Icons.storefront, color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: OneUiSpacing.xxl),
              // Title
              Center(
                child: Text(
                  'Sign in to Soko Vibe',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                    color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: OneUiSpacing.sm),
              Center(
                child: Text(
                  'Welcome back! Please sign in to continue',
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: OneUiSpacing.huge),
              // Email field
              Text(
                'Email',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                ),
              ),
              const SizedBox(height: OneUiSpacing.sm),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Enter your email',
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: OneUiSpacing.xl),
              // Password field
              Text(
                'Password',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                ),
              ),
              const SizedBox(height: OneUiSpacing.sm),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: OneUiSpacing.md),
              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(AppRoutes.forgotPassword),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: OneUiSpacing.xxl),
              // Sign in button
              FilledButton(
                onPressed: _isLoading ? null : _handleSignIn,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Sign In'),
              ),
              const SizedBox(height: OneUiSpacing.xl),
              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: isDark ? OneUiColors.darkBorder : OneUiColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: OneUiSpacing.lg),
                    child: Text(
                      'or',
                      style: TextStyle(color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
                    ),
                  ),
                  Expanded(child: Divider(color: isDark ? OneUiColors.darkBorder : OneUiColors.border)),
                ],
              ),
              const SizedBox(height: OneUiSpacing.xl),
              // Google sign in
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: OneUiSpacing.huge),
              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => context.push('/oneui/register'),
                    child: const Text('Sign Up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSignIn() {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }
}
