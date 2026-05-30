import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../extensions/context_tr.dart';
import '../../services/auth_service.dart';
import '../../app/routes.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _authService = AuthService();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await _authService.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(context.tr('email_verification_sent')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("${context.tr('error')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerification() async {
    final verified = await _authService.isEmailVerified();
    if (verified && mounted) {
      context.replace(AppRoutes.home);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text(context.tr('email_not_verified')),
        ),
      );
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
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mark_email_unread,
                        size: 80,
                        color: cs.primary,
                      ),
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
                        context.tr('verify_email_sent'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.6),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _checkVerification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
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
                        onPressed: _sending ? null : _resend,
                        child: _sending
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              )
                            : Text(
                                context.tr('resend_verification'),
                                style: TextStyle(color: cs.primary),
                              ),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () async {
                          await _authService.logout();
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Text(
                          context.tr('use_different_account'),
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

