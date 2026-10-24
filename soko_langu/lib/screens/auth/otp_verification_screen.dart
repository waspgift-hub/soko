import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../extensions/context_tr.dart';
import '../../models/otp_verification_models.dart';
import '../../services/otp_verification_controller.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/auth/auth_success_check.dart';
import '../../widgets/ds/ds_button.dart';
import '../../widgets/soko_vibe_loading.dart';

/// Universal OTP verification screen used by every OTP flow in Soko Vibe.
///
/// Design requirements:
/// * Single OTP input field — no individual boxes, no square containers,
///   no input cards.
/// * Premium, minimal appearance with large readable digits, character
///   spacing, and a subtle continuous underline.
/// * Soko Vibe brand colors (black/white canvas + #00C853 green accent).
/// * Swahili + English via [context.tr].
///
/// The screen is driven by [OtpVerificationController] and an
/// [OtpVerificationRequest] that carries the flow-specific context (purpose,
/// destination, masked destination, OTP length, callbacks). Each flow keeps
/// its own backend verification operation — the UI is shared, the business
/// logic is not.
///
/// The caller's [OtpVerificationRequest.onVerify] is responsible for calling
/// the correct backend verification endpoint for the flow (phone login,
/// email login, registration, password reset, etc.) and returning an
/// authoritative [OtpVerificationResult]. The screen never synthesizes a
/// verified state locally.
///
/// Usage:
/// ```dart
/// context.pushNamed(AppRoutes.otpVerification, extra: OtpVerificationRequest(
///   purpose: OtpPurpose.phoneLogin,
///   destination: '+255712345678',
///   maskedDestination: '+255 *** *** 482',
///   channel: OtpChannel.phone,
///   onVerify: (otp) => authNotifier.loginWithPhone(phone, otp).then((_) =>
///       const OtpVerificationResult.success()),
///   onResend: () => authNotifier.sendPhoneOtp(phone).then((_) =>
///       const OtpVerificationResult.success()),
///   allowDestinationEdit: true,
///   allowResend: true,
/// ));
/// ```
class OtpVerificationScreen extends StatefulWidget {
  final OtpVerificationRequest request;

  const OtpVerificationScreen({super.key, required this.request});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  late final OtpVerificationController _controller;
  String _otpValue = '';

  @override
  void initState() {
    super.initState();
    _controller = OtpVerificationController(request: widget.request);
    _controller.initialize();
  }

  @override
  void didUpdateWidget(OtpVerificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _controller.dispose();
      _controller = OtpVerificationController(request: widget.request);
      _controller.initialize();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _t(String key, String fallback) => context.tr(key, fallback);
  String _tParams(String key, Map<String, String> params) =>
      context.trParams(key, params);

  Future<void> _handleVerify() async {
    await _controller.verify(_otpValue);
    // The caller's onVerify (invoked inside controller.verify) handles
    // backend verification and navigation. The screen only reacts to phase
    // changes, so nothing more is needed here.
  }

  Future<void> _handleResend() async {
    await _controller.resend();
  }

  String _formatSeconds(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final request = widget.request;

    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<OtpVerificationController>(
        builder: (context, controller, _) {
          return PopScope(
            canPop: controller.phase != OtpVerificationPhase.verifying,
            child: _AuthSceneShell(
              heading: request.headingOverride ??
                  _t('verify_your_number', 'Thibitisha akaunti yako'),
              subtitle: request.subtitleOverride ??
                  _tParams('enter_code_sent', {'0': request.maskedDestination}),
              leading: _BackButton(
                  enabled: controller.phase != OtpVerificationPhase.verifying),
              child: controller.phase == OtpVerificationPhase.verified
                  ? const _SuccessView()
                  : Column(
                      key: const ValueKey('otp_form'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          request.maskedDestination,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s3),
                        OtpInputField(
                          length: request.otpLength,
                          value: _otpValue,
                          enabled: controller.phase !=
                                  OtpVerificationPhase.verified &&
                              controller.phase !=
                                  OtpVerificationPhase.expired,
                          hasError: controller.phase ==
                              OtpVerificationPhase.error,
                          onChanged: (v) => setState(() => _otpValue = v),
                          onSubmitted: () => _handleVerify(),
                          digitPositionLabel:
                              _t('otp_digit_position', 'Nafasi ya namba'),
                        ),
                        const SizedBox(height: AppSpacing.s3),
                        if (controller.errorMessage != null) ...[
                          Text(
                            controller.errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                        ],
                        if (controller.phase != OtpVerificationPhase.expired)
                          ...[
                            const SizedBox(height: AppSpacing.s2),
                            Center(
                              child: Text(
                                _t('otp_expires_in', 'IMETAISHA MDA: {0}')
                                    .replaceAll('{0}',
                                        _formatSeconds(controller.expiryLeft)),
                                style: TextStyle(
                                  color: controller.expiryLeft < 60
                                      ? cs.error
                                      : cs.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        const SizedBox(height: AppSpacing.s5),
                        DsButton(
                          label: _t('verify', 'Thibitisha'),
                          onPressed: controller.verifying || controller.success
                              ? null
                              : _handleVerify,
                          loading: controller.verifying,
                          icon: Icons.verified_user_outlined,
                          height: 52,
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Center(
                          child: controller.sending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : controller.canResend && request.allowResend
                              ? TextButton.icon(
                                  onPressed: _handleResend,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: Text(
                                      _t('resend_code', 'Tuma Msimbo Tena')),
                                )
                              : Text(
                                  _t('resend_wait', 'Subiri sekunde {0}...')
                                      .replaceAll(
                                          '{0}', '${controller.resendLeft}s'),
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        if (request.allowDestinationEdit)
                          Center(
                            child: TextButton(
                              onPressed: controller.verifying
                                  ? null
                                  : () => Navigator.of(context).maybePop(),
                              child: Text(
                                _t(
                                    'change_destination',
                                    'Badilisha namba/barua pepe'),
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  decoration: TextDecoration.underline,
                                  decorationColor: cs.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Success view shown after backend-confirmed verification.
class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const AnimatedSuccessCheck(size: 72),
          const SizedBox(height: AppSpacing.s4),
          Text(
            context.tr('verified', 'Umethibitishwa'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface),
          ),
          const SizedBox(height: AppSpacing.s2),
          const SizedBox(height: AppSpacing.s5),
          const SizedBox(
              width: 120,
              child: SokoVibeThreeDotLoader(size: 26, dotSize: 6)),
        ],
      ),
    );
  }
}

/// Back button that disables itself during verification so the user cannot
/// back-navigate out of a mandatory verification mid-flight.
class _BackButton extends StatelessWidget {
  final bool enabled;

  const _BackButton({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? () => Navigator.of(context).maybePop() : null,
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      tooltip: 'Rudi',
    );
  }
}

/// Shell reused by the OTP screen. Mirrors [AuthScene] structure so the OTP
/// screen looks consistent with the rest of the auth surfaces but keeps its
/// own layout control (single OTP field, no boxes).
class _AuthSceneShell extends StatelessWidget {
  final String heading;
  final String subtitle;
  final Widget leading;
  final Widget child;

  const _AuthSceneShell({
    required this.heading,
    required this.subtitle,
    required this.leading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 64,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 12),
                  const Icon(Icons.storefront_outlined, size: 24,
                      color: Color(0xFF00C853)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Soko Vibe',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontFamily: 'Space Grotesk')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height - 64),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          heading,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.6,
                              color: cs.onSurface),
                        ),
                        const SizedBox(height: AppInsets.md),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 15,
                              height: 1.4),
                        ),
                        const SizedBox(height: AppInsets.xxl),
                        child,
                        const SizedBox(height: AppInsets.xxl),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
