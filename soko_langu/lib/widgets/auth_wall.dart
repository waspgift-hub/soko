import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/routes.dart';
import '../extensions/context_tr.dart';
import '../theme/app_dimens.dart';

/// Returns true when a user is signed in. Otherwise shows the
/// authentication wall (bottom sheet with login CTA) and returns false.
/// Callers must not perform the write action when false is returned.
Future<bool> requireAuth(BuildContext context) async {
  if (FirebaseAuth.instance.currentUser != null) return true;
  if (!context.mounted) return false;
  final login = await showModalBottomSheet<bool>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Icon(Icons.lock_outline,
                size: 44,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              context.tr('login_required_title', 'Ingia kuendelea'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('login_required_body',
                  'You need an account to do this. Browsing is free.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppRadius.lg)),
                ),
                child: Text(
                    context.tr('login', 'Ingia')),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                  context.tr('maybe_later', 'Baadaye')),
            ),
          ],
        ),
      ),
    ),
  );
  if (login == true && context.mounted) {
    context.push(AppRoutes.login);
  }
  return false;
}
