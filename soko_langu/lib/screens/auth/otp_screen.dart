import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../extensions/context_tr.dart';
import '../../models/otp_verification_models.dart';
import '../../services/otp_verification_controller.dart';
import '../../notifiers/auth_notifier.dart';
import '../../screens/auth/otp_verification_screen.dart';

/// Verifies a code typed on the OTP screen. Returns `null` on success, or a
/// user-facing error message to show inline. The screen stays generic: the
/// caller owns all auth/navigation logic.
typedef OtpVerifier = Future<String?> Function(BuildContext context, String otp);

/// Backward-compatible wrapper around the universal [OtpVerificationScreen].
///
/// Existing callers (e.g. [RegisterScreen]) that import `otp_screen.dart`
/// continue to work unchanged. The wrapper translates the legacy
/// [OtpVerifier]/[onSuccess] API into the new [OtpVerificationRequest]
/// contract and delegates rendering to [OtpVerificationScreen].
class OtpScreen extends StatelessWidget {
  final String phone;
  final String displayPhone;
  final OtpVerifier verify;
  final void Function(BuildContext context) onSuccess;
  final int resendSeconds;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.displayPhone,
    required this.verify,
    required this.onSuccess,
    this.resendSeconds = 60,
  });

  @override
  Widget build(BuildContext context) {
    return OtpVerificationScreen(
      request: OtpVerificationRequest(
        purpose: OtpPurpose.phoneLogin,
        destination: phone,
        maskedDestination: displayPhone,
        channel: OtpChannel.phone,
        otpLength: 6,
        langCode: 'sw',
        onVerify: (otp) async {
          final error = await verify(context, otp);
          if (error == null) {
            onSuccess(context);
            return const OtpVerificationResult.success();
          }
          return OtpVerificationResult.failure(
            errorCode: error,
            userMessage: error,
          );
        },
        onResend: () async {
          await context.read<AuthNotifier>().sendPhoneOtp(phone);
          return const OtpVerificationResult.success();
        },
        allowDestinationEdit: true,
        allowResend: true,
      ),
    );
  }
}
