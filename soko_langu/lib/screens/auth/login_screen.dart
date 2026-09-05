import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/saved_account.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/account_manager.dart';
import '../../theme/app_colors.dart';
import '../../widgets/auth/auth_scene.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
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

  Future<void> _onGoogleLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().signInWithGoogle();
      await _saveAccount('google');
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
      heading: context.tr('welcome_back'),
      subtitle: context.tr('login_subtitle'),
      leading: const _BackButton(),
      child: AuthCard(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GoogleButton(onPressed: _isLoading ? null : _onGoogleLogin),
              const SizedBox(height: 14),
              // Google is the only sign-in method — no password to forget,
              // so the reassurance note replaces the old email/phone forms.
              Text(
                'Hutahitaji neno la siri. Akaunti yako ya Google ndiyo njia pekee ya kuingia.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
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
      tooltip: 'Back',
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
            // Official Google-hosted "G" — matches dark and light themes, so
            // no app asset to keep in sync with Google's branding.
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