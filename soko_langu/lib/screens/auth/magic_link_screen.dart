import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../notifiers/auth_notifier.dart';
import '../../widgets/auth_form_widgets.dart';

class MagicLinkScreen extends StatefulWidget {
  const MagicLinkScreen({super.key});

  @override
  State<MagicLinkScreen> createState() => _MagicLinkScreenState();
}

class _MagicLinkScreenState extends State<MagicLinkScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('enter_email');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return context.tr('invalid_email');
    }
    return null;
  }

  Future<void> _sendLink() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = context.read<AuthNotifier>();
    await notifier.sendMagicLink(_emailController.text.trim());

    if (!mounted) return;

    if (notifier.error != null) {
      _showError(notifier.error!);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<AuthNotifier>(
      builder: (context, notifier, _) {
        final isSent = notifier.magicLinkState == MagicLinkState.sent;
        final isSending = notifier.magicLinkState == MagicLinkState.sending;

        return Stack(
          children: [
            AuthPageShell(
              title: context.tr('app_name'),
              subtitle: isSent
                  ? context
                        .tr('link_sent_to')
                        .replaceAll('{0}', _emailController.text.trim())
                  : context.tr('login_with_email_link'),
              footer: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(context.tr('no_account')),
                  GestureDetector(
                    onTap: isSending
                        ? null
                        : () => context.push(AppRoutes.register),
                    child: Text(
                      context.tr('register'),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              child: AuthGlassCard(
                child: isSent ? _buildSentState(context) : _buildForm(cs),
              ),
            ),
            AuthLoadingOverlay(visible: isSending),
          ],
        );
      },
    );
  }

  Widget _buildForm(ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            decoration: authInputDecoration(
              context,
              hint: context.tr('email'),
              icon: Icons.email_outlined,
            ),
            validator: _emailValidator,
            onFieldSubmitted: (_) => _sendLink(),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: context.tr('send_link'),
            onPressed: _sendLink,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              context.tr('back_to_login'),
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentState(BuildContext context) {
    final email = _emailController.text.trim();
    return Column(
      children: [
        Icon(
          Icons.mark_email_unread,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('check_your_email'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('magic_link_sent_body').replaceAll('{0}', email),
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: context.tr('resend_link'),
          onPressed: _sendLink,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.read<AuthNotifier>().resetMagicLink(),
          child: Text(context.tr('change_email')),
        ),
      ],
    );
  }
}
