import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../extensions/context_tr.dart';
import '../../notifiers/auth_notifier.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/auth/auth_otp_field.dart';
import '../../widgets/auth/auth_scene.dart';
import '../../widgets/auth/auth_success_check.dart';
import '../../widgets/ds/ds_button.dart';
import '../../widgets/soko_vibe_loading.dart';

/// Verifies a code typed on the OTP screen. Returns `null` on success, or a
/// user-facing error message to show inline. The screen stays generic: the
/// caller owns all auth/navigation logic.
typedef OtpVerifier = Future<String?> Function(BuildContext context, String otp);

/// Single OTP entry point for the whole app.
///
/// Renders six auto-advancing boxes with paste support, a spam-protected
/// resend countdown, clipboard detection, success/error animations and a
/// "change phone number" escape hatch back to the caller.
class OtpScreen extends StatefulWidget {
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
    this.resendSeconds = 45,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpKey = GlobalKey<AuthOtpFieldState>();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _canResend = false;
  bool _resending = false;
  bool _verifying = false;
  bool _success = false;
  String? _errorMessage;
  int _errorTick = 0;
  String? _clipboardCode;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _detectClipboardOtp();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _canResend = false;
      _secondsLeft = widget.resendSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _canResend = true;
          _timer?.cancel();
        }
      });
    });
  }

  String get _resendLabel {
    final mm = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_secondsLeft % 60).toString().padLeft(2, '0');
    return context.tr('resend_wait').replaceAll('{0}', '$mm:$ss');
  }

  Future<void> _detectClipboardOtp() async {
    // Deferred so detection does not compete with the route transition.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      final match = RegExp(r'\b(\d{6})\b').firstMatch(text);
      if (match != null) {
        setState(() => _clipboardCode = match.group(1));
      }
    } catch (_) {
      // Clipboard can throw on some platforms; silently ignore.
    }
  }

  void _applyClipboardCode() {
    final code = _clipboardCode;
    if (code == null) return;
    _otpKey.currentState?.setCode(code);
    setState(() => _clipboardCode = null);
  }

  Future<void> _verify([String? explicitOtp]) async {
    if (_verifying || _success) return;
    final otp = explicitOtp ?? _otpKey.currentState?.code ?? '';
    if (otp.length != 6) {
      setState(() {
        _errorMessage = context.tr('enter_otp_6_digits');
        _errorTick++;
      });
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });
    final error = await widget.verify(context, otp);
    if (!mounted) return;
    if (error == null) {
      HapticFeedback.heavyImpact();
      setState(() => _success = true);
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted) widget.onSuccess(context);
      });
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _verifying = false;
        _errorMessage = error;
        _errorTick++;
      });
    }
  }

  Future<void> _resend() async {
    if (!_canResend || _resending) return;
    setState(() => _resending = true);
    try {
      await context.read<AuthNotifier>().sendPhoneOtp(widget.phone);
      _startCountdown();
      if (mounted) {
        _otpKey.currentState?.clear();
        setState(() => _errorMessage = null);
      }
    } catch (_) {
      // sendPhoneOtp consumes the error into notifier.error; nothing to rethrow.
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_verifying,
      child: AuthScene(
        heading: context.tr('verify_your_number'),
        subtitle: context.trParams('enter_code_sent', {'0': widget.displayPhone}),
        leading: _BackButton(enabled: !_verifying),
        child: AuthCard(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _success
                ? _SuccessView(
                    key: const ValueKey('success'),
                    displayPhone: widget.displayPhone,
                  )
                : Column(
                    key: const ValueKey('form'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.displayPhone,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s6),
                      AuthOtpField(
                        key: _otpKey,
                        errorTick: _errorTick,
                        onCompleted: (_) => _verify(),
                        autofocus: true,
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _errorMessage != null
                            ? Text(
                                _errorMessage!,
                                key: ValueKey(_errorTick),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : const SizedBox(height: 2),
                      ),
                      if (_clipboardCode != null) ...[
                        const SizedBox(height: AppSpacing.s2),
                        Center(
                          child: TextButton.icon(
                            onPressed: _applyClipboardCode,
                            icon: Icon(
                              Icons.content_paste_go,
                              size: 18,
                              color: cs.primary,
                            ),
                            label: Text(
                              context.tr('paste_otp'),
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s5),
                      DsButton(
                        label: context.tr('verify'),
                        onPressed: () => _verify(),
                        loading: _verifying,
                        icon: Icons.verified_user_outlined,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Center(
                        child: _resending
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: cs.primary,
                                  ),
                                ),
                              )
                            : _canResend
                                ? TextButton.icon(
                                    onPressed: _resend,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: Text(context.tr('resend_code')),
                                  )
                                : Text(
                                    _resendLabel,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Center(
                        child: TextButton(
                          onPressed: _verifying
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: Text(
                            context.tr('change_phone'),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              decoration: TextDecoration.underline,
                              decorationColor: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final bool enabled;

  const _BackButton({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? () => Navigator.of(context).maybePop() : null,
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      tooltip: 'Back',
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String displayPhone;

  const _SuccessView({super.key, required this.displayPhone});

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
            context.tr('verified'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            displayPhone,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          const SizedBox(
            width: 120,
            child: SokoVibeThreeDotLoader(
              size: 26,
              dotSize: 6,
            ),
          ),
        ],
      ),
    );
  }
}