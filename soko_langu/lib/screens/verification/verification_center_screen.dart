import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../models/seller_verification.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/seller_verification_service.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/animations/soko_animated_illustration.dart';
import '../../widgets/ds/ds_card.dart';

/// Single hub for authentication assurance, contact verification, MFA, and KYC.
///
/// Status labels are derived from Firebase Auth + [SellerVerificationService].
/// This screen never writes verification state — CTAs open the real flows.
class VerificationCenterScreen extends StatefulWidget {
  const VerificationCenterScreen({super.key});

  @override
  State<VerificationCenterScreen> createState() =>
      _VerificationCenterScreenState();
}

class _VerificationCenterScreenState extends State<VerificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SellerVerificationService>().refresh();
      context.read<AuthNotifier>().loadMfaState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final auth = context.watch<AuthNotifier>();
    final verification = context.watch<SellerVerificationService>();
    final self = verification.selfVerification;

    final emailVerified = user?.emailVerified == true;
    final hasPhone = (user?.phoneNumber ?? '').isNotEmpty;
    final mfaEnrolled = auth.mfaEnrolled;
    final kycStatus = self.kycStatus;
    final blueTick = self.isBlueTickActive;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('verification_center_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: [
            Center(
              child: SokoAnimatedIllustration(
                kycStatus == KycStatus.approved
                    ? SokoIllustration.kycVerified
                    : SokoIllustration.kycPending,
                size: 120,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              context.tr('verification_center_subtitle'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium(cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.s5),
            _StatusCard(
              icon: Icons.person_outline,
              title: context.tr('vc_auth_title'),
              statusLabel: user != null
                  ? context.tr('vc_status_signed_in')
                  : context.tr('vc_status_signed_out'),
              status: user != null
                  ? _VcStatus.verified
                  : _VcStatus.required,
              body: context.tr('vc_auth_body'),
              actionLabel:
                  user == null ? context.tr('login') : null,
              onAction: user == null
                  ? () => context.push(AppRoutes.login)
                  : null,
            ),
            _StatusCard(
              icon: Icons.email_outlined,
              title: context.tr('vc_email_title'),
              statusLabel: emailVerified
                  ? context.tr('vc_status_verified')
                  : context.tr('vc_status_required'),
              status: emailVerified
                  ? _VcStatus.verified
                  : _VcStatus.required,
              body: emailVerified
                  ? (user?.email ?? '')
                  : context.tr('vc_email_body'),
              actionLabel: emailVerified
                  ? null
                  : context.tr('vc_email_action'),
              onAction: emailVerified
                  ? null
                  : () => context.push(
                        AppRoutes.verifyEmail,
                        extra: {'email': user?.email ?? ''},
                      ),
            ),
            _StatusCard(
              icon: Icons.phone_iphone_outlined,
              title: context.tr('vc_phone_title'),
              statusLabel: hasPhone
                  ? context.tr('vc_status_linked')
                  : context.tr('vc_status_not_started'),
              status: hasPhone
                  ? _VcStatus.verified
                  : _VcStatus.notStarted,
              body: hasPhone
                  ? (user?.phoneNumber ?? '')
                  : context.tr('vc_phone_body'),
              actionLabel: hasPhone
                  ? null
                  : context.tr('vc_phone_action'),
              onAction: hasPhone
                  ? null
                  : () => context.push(AppRoutes.kyc),
            ),
            _StatusCard(
              icon: Icons.security_outlined,
              title: context.tr('vc_mfa_title'),
              statusLabel: mfaEnrolled
                  ? context.tr('vc_status_enrolled')
                  : context.tr('vc_status_not_enrolled'),
              status: mfaEnrolled
                  ? _VcStatus.verified
                  : _VcStatus.recommended,
              body: context.tr('vc_mfa_body'),
              actionLabel: mfaEnrolled
                  ? null
                  : context.tr('vc_mfa_action'),
              onAction: mfaEnrolled
                  ? null
                  : () => context.push(AppRoutes.mfaEnrollment),
            ),
            _StatusCard(
              icon: Icons.badge_outlined,
              title: context.tr('vc_kyc_title'),
              statusLabel: _kycLabel(context, kycStatus),
              status: _kycVcStatus(kycStatus),
              body: context.tr('vc_kyc_body'),
              actionLabel: context.tr('vc_kyc_action'),
              onAction: () => context.push(AppRoutes.kyc),
            ),
            _StatusCard(
              icon: Icons.verified_outlined,
              title: context.tr('vc_blue_tick_title'),
              statusLabel: blueTick
                  ? context.tr('vc_status_active')
                  : context.tr('vc_status_not_eligible'),
              status: blueTick
                  ? _VcStatus.verified
                  : _VcStatus.notStarted,
              body: context.tr('vc_blue_tick_body'),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              context.tr('vc_footer_note'),
              style: AppTypography.caption(cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _kycLabel(BuildContext context, KycStatus status) {
    switch (status) {
      case KycStatus.approved:
        return context.tr('vc_status_verified');
      case KycStatus.pending:
        return context.tr('vc_status_under_review');
      case KycStatus.rejected:
      case KycStatus.revoked:
        return context.tr('vc_status_action_required');
      case KycStatus.none:
        return context.tr('vc_status_not_started');
    }
  }

  _VcStatus _kycVcStatus(KycStatus status) {
    switch (status) {
      case KycStatus.approved:
        return _VcStatus.verified;
      case KycStatus.pending:
        return _VcStatus.inProgress;
      case KycStatus.rejected:
      case KycStatus.revoked:
        return _VcStatus.actionRequired;
      case KycStatus.none:
        return _VcStatus.notStarted;
    }
  }
}

enum _VcStatus {
  verified,
  required,
  recommended,
  notStarted,
  inProgress,
  actionRequired,
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.statusLabel,
    required this.status,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String statusLabel;
  final _VcStatus status;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  Color _statusColor(ColorScheme cs) {
    switch (status) {
      case _VcStatus.verified:
        return cs.primary;
      case _VcStatus.required:
      case _VcStatus.actionRequired:
        return cs.error;
      case _VcStatus.inProgress:
        return cs.tertiary;
      case _VcStatus.recommended:
        return cs.secondary;
      case _VcStatus.notStarted:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(cs);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: DsCard(
        onTap: onAction,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.cardTitle(cs.onSurface)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTypography.statusChip(color),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(body, style: AppTypography.bodySmall(cs.onSurfaceVariant)),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      actionLabel!,
                      style: AppTypography.buttonTextSmall(cs.primary),
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null)
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
