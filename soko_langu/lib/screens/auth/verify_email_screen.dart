import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../extensions/context_tr.dart';
import '../../models/otp_verification_models.dart';
import '../../notifiers/auth_notifier.dart';
import '../../app/routes.dart';
import '../../screens/auth/otp_verification_screen.dart';

/// Verifies the signed-in user's (or supplied) email via OTP.
///
/// Delegates to the universal [OtpVerificationScreen] so all email OTP
/// flows share one premium, box-free input UI. Backend verification is
/// handled by [AuthNotifier.verifyEmailOtp] via the request's [onVerify].
class VerifyEmailScreen extends StatefulWidget {
  final String? email;

  const VerifyEmailScreen({super.key, this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  String? _email;

  @override
  void initState() {
    super.initState();
    _email = widget.email;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email == null || _email!.isEmpty) {
      final extraEmail = GoRouterState.of(context).extra is Map
          ? (GoRouterState.of(context).extra as Map)['email'] as String?
          : null;
      _email = extraEmail ?? FirebaseAuth.instance.currentUser?.email;
    }
  }

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}***@${email.substring(at + 1)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_email == null || _email!.isEmpty) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ] else ...[
                  Icon(Icons.mark_email_unread, size: 80, color: cs.primary),
                  const SizedBox(height: 24),
                  Text(
                    context.tr('verify_email_title'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('otp_will_be_sent_to_email'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _email!,
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => _sendOtp(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        context.tr('send_otp'),
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendOtp(BuildContext context) async {
    if (_email == null || _email!.isEmpty) return;
    try {
      await context.read<AuthNotifier>().sendEmailOtp(_email!);
      if (!mounted) return;
      context.pushNamed(AppRoutes.otpVerification, extra: OtpVerificationRequest(
        purpose: OtpPurpose.emailLogin,
        destination: _email!,
        maskedDestination: _maskEmail(_email!),
        channel: OtpChannel.email,
        otpLength: 6,
        langCode: 'sw',
        onVerify: (otp) async {
          final ok = await context.read<AuthNotifier>().verifyEmailOtp(_email!, otp);
          if (ok && mounted) {
            context.go(AppRoutes.home);
          }
          return const OtpVerificationResult.success();
        },
        onResend: () async {
          await context.read<AuthNotifier>().sendEmailOtp(_email!);
          return const OtpVerificationResult.success();
        },
        allowDestinationEdit: false,
        allowResend: true,
        headingOverride: context.tr('verify_email_title'),
        subtitleOverride: context.tr('enter_otp_email_sent'),
      ));
    } catch (_) {
      // AuthNotifier.error is surfaced by the notifier; the screen will show
      // it via its error state when the user retries.
    }
  }
}
