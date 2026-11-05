import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../../services/banner_service.dart';
import 'campaign_banner_card.dart';

/// Renders admin-configured campaign banners for a [placement] (NOT AdMob).
/// Uses [BannerService] stream/cache; does not mutate AdMob services.
/// Do not use in checkout/payment-critical flows.
class CampaignBannerSlot extends StatefulWidget {
  const CampaignBannerSlot({super.key, required this.placement, this.bannerService, this.margin});

  final BannerPlacement placement;
  final BannerService? bannerService;
  final EdgeInsetsGeometry? margin;

  @override
  State<CampaignBannerSlot> createState() => _CampaignBannerSlotState();
}

class _CampaignBannerSlotState extends State<CampaignBannerSlot> {
  BannerService? _owned;
  StreamSubscription<Map<BannerPlacement, List<BannerCampaign>>>? _sub;
  List<BannerCampaign> _items = const [];
  final Set<String> _impressionRecorded = <String>{};

  BannerService get _service => widget.bannerService ?? (_owned ??= BannerService());

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant CampaignBannerSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bannerService != widget.bannerService ||
        oldWidget.placement != widget.placement) {
      _unbind();
      _bind();
    }
  }

  void _bind() {
    final svc = _service;
    _items = svc.getBannersForPlacement(widget.placement);
    _sub = svc.bannersStream.listen((map) {
      if (!mounted) return;
      setState(() => _items = map[widget.placement] ?? const []);
    });
    if (widget.bannerService == null) {
      // Best-effort start for standalone usage; screens may also manage lifecycle.
      unawaited(svc.start());
    }
  }

  void _unbind() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _unbind();
    _owned?.dispose();
    super.dispose();
  }

  void _recordImpressionOnce(BannerCampaign c) {
    if (_impressionRecorded.add(c.id)) {
      unawaited(_service.recordImpression(bannerId: c.id, placement: widget.placement));
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _items.where((c) => c.placement == widget.placement).toList();
    if (eligible.isEmpty) return const SizedBox.shrink();
    // Render highest-priority eligible campaign for this slot.
    final campaign = eligible.first;
    _recordImpressionOnce(campaign);
    final card = CampaignBannerCard(
      campaign: campaign,
      onImpressionRecorded: () {}, // handled by slot to avoid duplicates
      onTap: () =>
          unawaited(_service.recordClick(bannerId: campaign.id, placement: widget.placement)),
    );
    if (widget.margin == null) return card;
    return Padding(padding: widget.margin!, child: card);
  }
}
