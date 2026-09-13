import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/buyer_request_model.dart';
import '../../services/buyer_request_service.dart';
import '../../widgets/rewarded_ad_gate.dart';
import '../../widgets/google_loading.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/soko_vibe_states.dart';

class BuyerRequestsScreen extends StatefulWidget {
  const BuyerRequestsScreen({super.key});

  @override
  State<BuyerRequestsScreen> createState() => _BuyerRequestsScreenState();
}

class _BuyerRequestsScreenState extends State<BuyerRequestsScreen> {
  final BuyerRequestService _service = BuyerRequestService();
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('buyer_requests_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.postBuyerRequest),
        icon: const Icon(Icons.add),
        label: Text(context.tr('post_request')),
      ),
      body: StreamBuilder<List<BuyerRequest>>(
        key: ValueKey('buyer_requests_$_refreshKey'),
        stream: _service.getRequests(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorState(
              detail: snap.error?.toString() ?? '',
              onRetry: () => setState(() => _refreshKey++),
            );
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading(size: 32));
          }
          final requests = snap.data!;
          if (requests.isEmpty) {
            return SokoVibeEmptyState(
              icon: Icons.search_off,
              title: context.tr('requests_empty'),
              subtitle: context.tr('requests_empty_hint'),
              actionLabel: context.tr('post_request'),
              onAction: () => context.push(AppRoutes.postBuyerRequest),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: requests.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildRequestCard(requests[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(BuyerRequest req) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final unlocked = req.isUnlockedFor(uid);

    return DsCard(
      padding: const EdgeInsets.all(16),
      color: cs.cardBase,
      radius: 18,
      border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      elevation: DsCardElevation.low,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DsAvatar(
                initials: _initials(req.buyerName.isEmpty ? req.buyerUid : req.buyerName),
                size: DsAvatarSize.md,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 14, color: cs.contentMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            req.buyerName.isEmpty ? req.buyerUid : req.buyerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.contentMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.schedule,
                            size: 13, color: cs.contentMuted),
                        const SizedBox(width: 3),
                        Text(
                          _relativeTime(req.createdAt),
                          style: TextStyle(fontSize: 12, color: cs.contentMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DsBadge(
                label: context.tr(unlocked ? 'contact_unlocked_short' : 'locked_short'),
                color: unlocked
                    ? cs.brandSuccess.withValues(alpha: 0.9)
                    : cs.contentMuted.withValues(alpha: 0.9),
                icon: unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              DsChip(
                label: '${context.tr('request_budget_label')}: ${context.formatPrice(req.budget)}',
                chipSize: DsChipSize.sm,
                selected: false,
                icon: Icons.monetization_on_outlined,
              ),
              const SizedBox(width: 8),
              const Spacer(),
              if (!unlocked)
                Icon(Icons.lock, size: 13, color: cs.contentMuted.withValues(alpha: 0.7)),
            ],
          ),
          if (req.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              req.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.contentSecondary, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          if (unlocked)
            DsButton(
              label: context.tr('whatsapp_contact'),
              size: DsButtonSize.sm,
              fullWidth: true,
              icon: Icons.chat,
              onPressed: () => _openWhatsApp(req.whatsapp),
            )
          else
            DsButton(
              label: context.tr('unlock_contact'),
              variant: DsButtonVariant.secondary,
              size: DsButtonSize.sm,
              fullWidth: true,
              icon: Icons.lock_open,
              onPressed: () => _unlock(req),
            ),
          if (!unlocked) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 12, color: cs.contentMuted.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  context.tr('locked_contact_hint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.contentMuted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first.trim();
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  String _relativeTime(DateTime time) {
    final d = DateTime.now().difference(time);
    if (d.inSeconds < 10) return context.tr('just_now');
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Future<void> _unlock(BuyerRequest req) async {
    final earned = await RewardedAdGate.require(
      context,
      'unlock_request_${req.id}',
      title: context.tr('unlock_contact'),
      message: context.tr('unlock_contact_ad_msg'),
    );
    if (!earned || !mounted) return;

    try {
      await _service.unlockContact(req.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('contact_unlocked')),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('imeshindwa').replaceAll('{0}', '$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String link) async {
    final uri = Uri.parse(link);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('phone_number_missing'))),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String detail;
  final VoidCallback onRetry;

  const _ErrorState({required this.detail, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: cs.error.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.cloud_off_rounded, size: 40, color: cs.error.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 18),
            Text(
              context.tr('requests_error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.contentPrimary),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.hairline),
                ),
                child: Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.contentMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('ignore_offline'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.contentMuted),
              ),
            ],
            const SizedBox(height: 18),
            DsButton(
              label: context.tr('retry'),
              variant: DsButtonVariant.secondary,
              size: DsButtonSize.md,
              fullWidth: false,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}