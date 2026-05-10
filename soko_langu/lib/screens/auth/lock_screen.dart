import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/secure_storage_service.dart';
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
  final _localAuth = LocalAuthentication();
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final reason = context.tr('unlock_app');
    try {
      final useBio = await SecureStorageService.read('use_biometric') == 'true';
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (mounted) setState(() => _biometricEnabled = useBio && (canCheck || supported));
      if (_biometricEnabled) {
        final authed = await _localAuth.authenticate(localizedReason: reason);
        if (authed && mounted) widget.onUnlock();
      }
    } catch (_) {}
  }

  Future<void> _unlock() async {
    final savedPin = await SecureStorageService.read('app_lock_pin') ?? '';
    if (_pinController.text == savedPin) {
      widget.onUnlock();
    } else {
      setState(() => _error = context.tr('wrong_pin'));
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 80, color: Colors.green[300]),
              const SizedBox(height: 24),
              Text(context.tr('enter_pin'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(
                  hintText: "******",
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _unlock,
                  child: Text(context.tr('unlock'),
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
              if (_biometricEnabled)
                IconButton(
                  icon: Icon(Icons.fingerprint, size: 40, color: Colors.green[400]),
                  onPressed: () => _checkBiometric(),
                  tooltip: 'Fingerprint',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
