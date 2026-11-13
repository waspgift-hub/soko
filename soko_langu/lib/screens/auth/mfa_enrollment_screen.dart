import 'dart:async';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../extensions/context_tr.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/mfa_service.dart';
import '../../widgets/ds/ds_button.dart';

/// Step in the MFA enrollment flow.
enum _MfaStep { intro, qr, verify, recovery, complete }

/// Screen for enrolling TOTP-based two-factor authentication.
///
/// Flow:
/// 1. Explain what MFA is and why it's needed
/// 2. Show QR code and manual entry secret
/// 3. User enters TOTP code from authenticator app
/// 4. Verify code with Firebase
/// 5. Show recovery codes (one-time display)
/// 6. Complete enrollment
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({super.key});

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  _MfaStep _step = _MfaStep.intro;
  MfaEnrollmentData? _enrollmentData;
  final _totpController = TextEditingController();
  Timer? _totpTimer;
  String _currentTotp = '';
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTotpTimer();
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _totpController.dispose();
    super.dispose();
  }

  void _startTotpTimer() {
    _totpTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_enrollmentData != null && _step == _MfaStep.qr) {
        setState(() {
          _currentTotp = _generateTotp(_enrollmentData!.secret);
        });
      }
    });
  }

  /// Local TOTP generation for display purposes only.
  /// Not used for actual verification (Firebase handles that).
  String _generateTotp(String base32Secret, {int timeStep = 30, int digits = 6}) {
    final secret = base32.decode(base32Secret);
    final counter = (DateTime.now().millisecondsSinceEpoch ~/ 1000) ~/ timeStep;
    final counterBytes = ByteData(8)..setInt64(0, counter, Endian.big);
    final hmac = Hmac(sha1, secret);
    final hash = hmac.convert(counterBytes.buffer.asUint8List()).bytes;
    final offset = hash.last & 0x0f;
    final code = ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);
    final otp = code % (10 ^ digits);
    return otp.toString().padLeft(digits, '0');
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _step = _MfaStep.qr;
      _isLoading = true;
      _error = null;
    });

    final authNotifier = context.read<AuthNotifier>();
    try {
      final data = await authNotifier.startMfaEnrollment();
      if (!mounted) return;
      setState(() {
        _enrollmentData = data;
        _isLoading = false;
        _error = null;
      });
    } on MfaError catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.userMessage;
      });
      _showErrorSnackBar(e.userMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = context.tr('mfa_enrollment_failed');
      });
      _showErrorSnackBar(context.tr('mfa_enrollment_failed'));
    }
  }

  Future<void> _verifyCode() async {
    final code = _totpController.text.replaceAll(' ', '');
    if (code.length != 6) {
      _showErrorSnackBar(context.tr('mfa_code_six_digits'));
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authNotifier = context.read<AuthNotifier>();
    try {
      await authNotifier.completeMfaEnrollment(code);
      if (!mounted) return;
      setState(() {
        _step = _MfaStep.recovery;
        _isLoading = false;
        _error = null;
      });
    } on MfaError catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = context.tr('mfa_verification_failed');
      });
    }
  }

  Future<void> _completeEnrollment() async {
    if (!mounted) return;
    setState(() => _step = _MfaStep.complete);

    // Brief delay to show completion screen
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    context.pop(true);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('copied_to_clipboard'))),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('mfa_enable_title')),
        leading: _step == _MfaStep.intro
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_step == _MfaStep.qr) {
                    setState(() => _step = _MfaStep.intro);
                  } else if (_step == _MfaStep.verify) {
                    setState(() => _step = _MfaStep.qr);
                  } else if (_step == _MfaStep.recovery) {
                    setState(() => _step = _MfaStep.verify);
                  }
                },
              ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    _buildStepContent(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _MfaStep.intro:
        return _buildIntroStep();
      case _MfaStep.qr:
        return _buildQrStep();
      case _MfaStep.verify:
        return _buildVerifyStep();
      case _MfaStep.recovery:
        return _buildRecoveryStep();
      case _MfaStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildIntroStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(
          Icons.security_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          context.tr('mfa_enable_title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('mfa_intro_explanation'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 32),
        DsButton(
          label: context.tr('mfa_get_started'),
          onPressed: _startEnrollment,
        ),
      ],
    );
  }

  Widget _buildQrStep() {
    if (_enrollmentData == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          context.tr('mfa_scan_qr'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('mfa_scan_qr_hint'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: QrImageView(
              data: _enrollmentData!.authUri,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.tr('mfa_manual_entry'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            _enrollmentData!.secret,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: Text(context.tr('copy_secret')),
          onPressed: () => _copyToClipboard(_enrollmentData!.secret),
        ),
        const SizedBox(height: 24),
        if (_currentTotp.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  context.tr('mfa_current_code'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _currentTotp,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 32),
        DsButton(
          label: context.tr('mfa_i_have_code'),
          onPressed: () => setState(() => _step = _MfaStep.verify),
        ),
      ],
    );
  }

  Widget _buildVerifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          context.tr('mfa_enter_code'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('mfa_enter_code_hint'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _totpController,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 16,
                fontWeight: FontWeight.w600,
              ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          onChanged: (value) {
            if (value.length == 6) _verifyCode();
          },
          autofocus: true,
        ),
        const SizedBox(height: 16),
        if (_currentTotp.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: Text(
              '${context.tr('mfa_current_code')}: $_currentTotp',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            onPressed: () => _copyToClipboard(_currentTotp),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = _MfaStep.qr),
          child: Text(context.tr('mfa_back_to_qr')),
        ),
      ],
    );
  }

  Widget _buildRecoveryStep() {
    if (_enrollmentData == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Icon(
          Icons.warning_amber_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('mfa_recovery_codes_title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('mfa_recovery_codes_warning'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: _enrollmentData!.recoveryCodes.map((code) {
            return InkWell(
              onTap: () => _copyToClipboard(code),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  code,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Text(
          context.tr('mfa_recovery_codes_note'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 32),
        DsButton(
          label: context.tr('mfa_i_saved_codes'),
          onPressed: _completeEnrollment,
        ),
      ],
    );
  }

  Widget _buildCompleteStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.check_circle_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          context.tr('mfa_enabled_success'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('mfa_enabled_description'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  }