import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../notifiers/auth_notifier.dart';
import '../../extensions/context_tr.dart';
import '../../services/account_manager.dart';
import '../../services/consent_recording_service.dart';
import '../../models/saved_account.dart';
import '../../widgets/soko_vibe_loading.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String email;
  final String password;
  final String displayName;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.email,
    required this.password,
    required this.displayName,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  int _resendSeconds = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendSeconds = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) _canResend = true;
      });
      return _resendSeconds > 0;
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _error = context.tr('enter_otp_6_digits'));
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final notifier = context.read<AuthNotifier>();
      final ok = await notifier.verifyPhoneOtp(widget.phone, otp);
      if (!ok) {
        setState(() { _error = context.tr(notifier.error ?? 'otp_invalid'); _isLoading = false; });
        return;
      }
      await notifier.register(
        email: widget.email,
        password: widget.password,
        displayName: widget.displayName,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'phone': widget.phone});
        await AccountManager.instance.addOrUpdateAccount(
          SavedAccount(
            uid: user.uid,
            email: user.email ?? '',
            displayName: widget.displayName,
            photoUrl: user.photoURL,
            provider: 'email',
            addedAt: DateTime.now(),
            isActive: true,
          ),
        );
        ConsentRecordingService.instance.recordConsent(user.uid);
      }
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() { _error = context.trError(e); _isLoading = false; });
    }
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthNotifier>().sendPhoneOtp(widget.phone);
      _startResendTimer();
    } catch (e) {
      setState(() => _error = context.trError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('enter_otp_title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.sms, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(context.tr('otp_code_hint'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(context.tr('otp_sent_to').replaceAll('{0}', widget.phone), style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: TextStyle(fontSize: 32, letterSpacing: 8, color: cs.onSurface, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: TextStyle(letterSpacing: 8, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verify,
                  style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: _isLoading ? SokoVibeThreeDotLoader(size: 22, dotSize: 5.5, color: cs.surface) : Text(context.tr('verify'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _canResend && !_isLoading ? _resend : null,
                child: Text(_canResend ? context.tr('resend_otp') : context.tr('resend_wait').replaceAll('{0}', '$_resendSeconds')),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
