import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_config.dart';
import '../theme/app_colors.dart';
import '../extensions/context_tr.dart';

/// Firestore-native seller Trust Passport (GET /api/trust/passport/:sellerId).
/// Loads the seller's verification, fulfillment, dispatch and dispute
/// indicators and renders them as a compact card. Fails silently when the
/// passport is unavailable so the order page never breaks.
class TrustPassportCard extends StatefulWidget {
  final String sellerId;

  const TrustPassportCard({super.key, required this.sellerId});

  @override
  State<TrustPassportCard> createState() => _TrustPassportCardState();
}

class _TrustPassportCardState extends State<TrustPassportCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(TrustPassportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId) {
      _loading = true;
      _data = null;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = {
      'Content-Type': 'application/json',
      if (user != null) 'Authorization': 'Bearer ${await user.getIdToken()}',
    };
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/trust/passport/${widget.sellerId}'),
        headers: headers,
      );
      final result = jsonDecode(resp.body);
      if (!mounted) return;
      setState(() {
        _data = result['data'] is Map
            ? Map<String, dynamic>.from(result['data'])
            : null;
        _loading = false;
      });
    } catch (_) {
      // Passport is best-effort; keep the order page resilient on failures.
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _levelColor(ColorScheme cs, String level) {
    switch (level) {
      case 'green':
        return cs.successGreen;
      case 'amber':
        return cs.brandWarning;
      case 'red':
        return cs.error;
      default:
        return cs.outline;
    }
  }

  String _indicatorLabel(String key) {
    switch (key) {
      case 'identity_verified':
        return context.tr('tp_identity_verified', 'Utambulisho umehakikiwa');
      case 'fulfillment':
        return context.tr('tp_fulfillment', 'Utekelezaji wa mauzo');
      case 'dispatch_punctuality':
        return context.tr('tp_dispatch_punctuality', 'Usafirishaji wa wakati');
      case 'dispute_behavior':
        return context.tr('tp_dispute_behavior', 'Tabia ya migogoro');
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const SizedBox.shrink();
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final seller = data['seller'] is Map
        ? Map<String, dynamic>.from(data['seller'])
        : const <String, dynamic>{};
    final indicators = (data['indicators'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final score = (seller['reliabilityScore'] as num?)?.toInt() ?? 0;
    final verified = seller['verificationStatus'] == 'verified';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.verified_user_outlined, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('tp_title', 'Trust ya Muuzaji'),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: cs.onSurface),
                    ),
                    Text(
                      seller['storeName'] as String? ?? '',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: verified ? 6 : 5),
                decoration: BoxDecoration(
                  color: verified
                      ? cs.successGreen.withValues(alpha: 0.12)
                      : cs.brandWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: verified
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified, color: cs.successGreen, size: 13),
                        const SizedBox(width: 4),
                        Text(context.tr('tp_verified', 'Imethibitishwa'),
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cs.successGreen)),
                      ])
                    : Text(context.tr('tp_unverified', 'Haijathibitishwa'),
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.brandWarning)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('tp_score', 'Alama ya Kuaminiwa'),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text('$score/100',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: cs.primary)),
                  ],
                ),
              ),
              Text(
                context.tr('tp_disclaimer', 'Hutengenezwa kutokana na miamala yake ya escrow.'),
                style: TextStyle(fontSize: 10.5, color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: cs.primary.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          ...indicators.map((ind) {
            final level = ind['level'] as String? ?? 'grey';
            final value = ind['value'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _levelColor(cs, level),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_indicatorLabel(ind['key'] as String? ?? ''),
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ),
                  if (value is num)
                    Text('$value%',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cs.onSurface)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
