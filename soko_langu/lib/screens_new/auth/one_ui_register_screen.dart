import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiRegisterScreen extends StatefulWidget {
  const OneUiRegisterScreen({super.key});

  @override
  State<OneUiRegisterScreen> createState() => _OneUiRegisterScreenState();
}

class _OneUiRegisterScreenState extends State<OneUiRegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _agreeTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
        title: Text(
          'Create Account',
          style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(OneUiSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Join Soko Vibe',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                ),
              ),
              const SizedBox(height: OneUiSpacing.sm),
              Text(
                'Create an account to start buying and selling',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary,
                ),
              ),
              const SizedBox(height: OneUiSpacing.xxl),
              _buildField('Full Name', _nameController, Icons.person_outline_rounded, false),
              const SizedBox(height: OneUiSpacing.lg),
              _buildField('Email', _emailController, Icons.email_outlined, false, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: OneUiSpacing.lg),
              _buildField('Phone Number', _phoneController, Icons.phone_outlined, false, keyboardType: TextInputType.phone),
              const SizedBox(height: OneUiSpacing.lg),
              _buildPasswordField('Password', _passwordController, _obscurePassword, () => setState(() => _obscurePassword = !_obscurePassword)),
              const SizedBox(height: OneUiSpacing.lg),
              _buildPasswordField('Confirm Password', _confirmPasswordController, _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
              const SizedBox(height: OneUiSpacing.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agreeTerms,
                    onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                    activeColor: OneUiColors.accent,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text.rich(
                        TextSpan(
                          text: 'I agree to the ',
                          style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
                          children: [
                            TextSpan(
                              text: 'Terms of Service',
                              style: TextStyle(color: OneUiColors.accent, fontWeight: FontWeight.w600),
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: TextStyle(color: OneUiColors.accent, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OneUiSpacing.xxl),
              FilledButton(
                onPressed: (_isLoading || !_agreeTerms) ? null : _handleRegister,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Text('Create Account'),
              ),
              const SizedBox(height: OneUiSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(color: isDark ? OneUiColors.darkTextSecondary : OneUiColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, bool obscure, {TextInputType? keyboardType}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
        const SizedBox(height: OneUiSpacing.sm),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            prefixIcon: Icon(icon, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool obscure, VoidCallback toggle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary)),
        const SizedBox(height: OneUiSpacing.sm),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            prefixIcon: Icon(Icons.lock_outline_rounded, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
            suffixIcon: IconButton(
              onPressed: toggle,
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: isDark ? OneUiColors.darkTextTertiary : OneUiColors.textTertiary),
            ),
          ),
        ),
      ],
    );
  }

  void _handleRegister() {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }
}
