import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/mfa_service.dart';
import '../../utils/network_error.dart';
import '../../widgets/auth/auth_scene.dart';
import '../../widgets/ds/ds_button.dart';

class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key, required this.resolver, this.email});

  final MultiFactorResolver resolver;
  final String? email;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_isLoading) return;
    final code = _codeController.text.replaceAll(RegExp(r'\s+'), '');
    if (code.length != 6) {
      setState(() => _error = context.tr('mfa_code_six_digits'));
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await context.read<AuthNotifier>().resolveMfaSignIn(widget.resolver, code);
      if (!mounted) return;
      context.go(AppRoutes.home);
    } on MfaError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.userMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = translateError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hint = widget.email ?? context.tr('your_account');
    return AuthScene(
      heading: context.tr('mfa_verify_title'),
      subtitle: context.trParams('mfa_verify_subtitle', {'0': hint}),
      child: AuthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
              ),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 24,
                letterSpacing: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
              onChanged: (v) {
                if (v.replaceAll(' ', '').length == 6) _verify();
              },
            ),
            const SizedBox(height: 16),
            DsButton(label: context.tr('verify'), loading: _isLoading, onPressed: _verify),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading ? null : () => context.go(AppRoutes.login),
              child: Text(context.tr('back_to_login')),
            ),
          ],
        ),
      ),
    );
  }
}
