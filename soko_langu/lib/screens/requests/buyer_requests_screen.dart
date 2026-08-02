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
    final cs = Theme.of(context).colorScheme;
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('requests_error'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _refreshKey++),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(context.tr('retry')),
                  ),
                ],
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: GoogleLoading(size: 32));
          }
          final requests = snap.data!;
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('requests_empty'),
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('requests_empty_hint'),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: requests.length,
            itemBuilder: (context, index) => _buildRequestCard(requests[index]),
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(BuyerRequest req) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final unlocked = req.isUnlockedFor(uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.search, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  req.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${context.tr('request_budget_label')}: ${context.formatPrice(req.budget)}',
              style: TextStyle(
                color: cs.secondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (req.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(req.description, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Text(
            req.buyerName.isEmpty ? req.buyerUid : req.buyerName,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: unlocked
                    ? ElevatedButton.icon(
                        onPressed: () => _openWhatsApp(req.whatsapp),
                        icon: const Icon(Icons.chat, size: 18),
                        label: Text(context.tr('whatsapp_contact')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.whatsappGreen,
                          foregroundColor: cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _unlock(req),
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: Text(context.tr('unlock_contact')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.tertiary,
                          side: BorderSide(color: cs.tertiary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (!unlocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.lock, size: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Text(
                    context.tr('locked_contact_hint'),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
