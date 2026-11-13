import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/secure_storage_service.dart';
import '../../services/app_lock_service.dart';
import '../../extensions/context_tr.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const LockScreen({super.key, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  int _attempts = 0;
  DateTime? _lockedUntil;

  /// Whether the biometric prompt has already been offered for this lock.
  ///
  /// Guards the automatic attempt on open. Apple and Google both prompt exactly
  /// once and then let the user choose: re-prompting on every rebuild turns a
  /// dismissed dialog into a dialog the user cannot escape.
  bool _promptedOnce = false;
  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    _maybePromptBiometric();
  }

  Future<void> _maybePromptBiometric() async {
    if (_promptedOnce) return;
    final lock = AppLockService.instance;
    if (!lock.usesBiometric) return;
    _promptedOnce = true;
    await _runBiometric();
  }

  Future<void> _runBiometric() async {
    if (_biometricBusy) return;
    setState(() {
      _biometricBusy = true;
      _error = null;
    });
    final result = await AppLockService.instance.authenticate();
    if (!mounted) return;
    setState(() {
      _biometricBusy = false;
      if (result.ok) return;
      // Say WHY, because "failed" and "locked out for 30s" need different words
      // and the PIN pad is the way out of both.
      _error = switch (result.outcome) {
        BiometricOutcome.lockedOut => context.tr('biometric_locked_out'),
        BiometricOutcome.unavailable => context.tr('biometric_unavailable'),
        BiometricOutcome.failed => context.tr('biometric_not_recognised'),
        BiometricOutcome.success => null,
      };
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      setState(() => _error = context.tr('too_many_attempts'));
      return;
    }
    final savedHash = await SecureStorageService.read('app_lock_pin') ?? '';
    // SHA-256 unsalted is weak for low-entropy PIN; kept for compat with
    // existing stored hashes, mitigated by attempt limit + backoff below.
    final inputHash = sha256.convert(utf8.encode(_pinController.text)).toString();
    if (inputHash == savedHash) {
      widget.onUnlock();
    } else {
      _attempts++;
      if (_attempts >= 5) {
        _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _attempts = 0;
      }
      if (!mounted) return;
      setState(() => _error = context.tr('wrong_pin'));
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock,
                        size: 56,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      context.tr('app_locked'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLockService.instance.usesBiometric
                          ? context.tr('enter_pin_unlock_fallback')
                          : context.tr('enter_pin_unlock'),
                      style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Semantics(
                        label: context.tr('enter_pin_unlock'),
                        textField: true,
                        child: TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          hintText: "• • • • • •",
                          hintStyle: TextStyle(
                            color: cs.outlineVariant,
                            letterSpacing: 12,
                            fontSize: 32,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 2,
                            ),
                          ),
                          errorText: _error,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 28,
                          letterSpacing: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        onSubmitted: (_) => _unlock(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Biometric first when it is enabled: it is one tap and no
                    // typing, which is why iOS and Android both lead with it.
                    // The PIN button stays regardless — a sensor that stops
                    // reading must never lock someone out of their account.
                    if (AppLockService.instance.usesBiometric) ...[
                      SizedBox(
                        width: 200,
                        child: FilledButton.tonalIcon(
                          onPressed: _biometricBusy ? null : _runBiometric,
                          icon: _biometricBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.fingerprint, size: 24),
                          label: Text(context.tr('unlock_biometric')),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: 200,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _unlock,
                        child: Text(
                          AppLockService.instance.usesBiometric
                              ? context.tr('unlock_with_pin')
                              : context.tr('unlock'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
