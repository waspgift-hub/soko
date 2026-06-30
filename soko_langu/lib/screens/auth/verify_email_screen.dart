import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../extensions/context_tr.dart';
import '../../notifiers/auth_notifier.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _otpController = TextEditingController();
  String? _email;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _email ??= GoRouterState.of(context).extra is Map
        ? (GoRouterState.of(context).extra as Map)['email'] as String?
        : null;
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_email == null || _email!.isEmpty) return;
    await context.read<AuthNotifier>().sendEmailOtp(_email!);
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) return;
    final notifier = context.read<AuthNotifier>();
    final ok = await notifier.verifyEmailOtp(_email ?? '', otp);
    if (ok && mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Consumer<AuthNotifier>(
          builder: (context, notifier, _) {
            final sending = notifier.emailOtpState == EmailOtpState.sending;
            final sent =
                notifier.emailOtpState == EmailOtpState.sent ||
                notifier.emailOtpState == EmailOtpState.verifying;
            final error = notifier.error;

            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            sent ? Icons.pin_rounded : Icons.mark_email_unread,
                            size: 80,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            sent
                                ? 'Ingiza OTP'
                                : context.tr('verify_email_title'),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            sent
                                ? 'Tuma OTP uliopokea kwenye barua pepe yako'
                                : 'OTP itatumwa kwenye barua pepe yako',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                              fontSize: 15,
                            ),
                          ),
                          if (_email != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _email!,
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (sent) ...[
                            const SizedBox(height: 32),
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
                                fillColor: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: cs.outlineVariant,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: cs.primary,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed:
                                    notifier.emailOtpState ==
                                        EmailOtpState.verifying
                                    ? null
                                    : _verifyOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child:
                                    notifier.emailOtpState ==
                                        EmailOtpState.verifying
                                    ? const GoogleLoading(
                                        size: 20,
                                        strokeWidth: 2,
                                      )
                                    : Text(
                                        context.tr('verified_continue'),
                                        style: TextStyle(
                                          color: cs.onPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: sending ? null : _sendOtp,
                              child: sending
                                  ? const GoogleLoading(
                                      size: 20,
                                      strokeWidth: 2,
                                    )
                                  : Text(
                                      'Tuma OTP tena',
                                      style: TextStyle(color: cs.primary),
                                    ),
                            ),
                          ] else ...[
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: sending ? null : _sendOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: sending
                                    ? const GoogleLoading(
                                        size: 20,
                                        strokeWidth: 2,
                                      )
                                    : Text(
                                        'Tuma OTP',
                                        style: TextStyle(
                                          color: cs.onPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                          if (error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: cs.error,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      error,
                                      style: TextStyle(
                                        color: cs.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () async {
                              await context.read<AuthNotifier>().logout();
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: Text(
                              context.tr('use_different_account'),
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
