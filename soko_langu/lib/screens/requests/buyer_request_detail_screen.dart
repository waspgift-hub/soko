import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/routes.dart';

import '../../extensions/context_tr.dart';
import '../../models/buyer_request_model.dart';
import '../../services/buyer_request_service.dart';
import '../../services/rewarded_ad_service.dart';

class BuyerRequestDetailScreen extends StatefulWidget {
  const BuyerRequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<BuyerRequestDetailScreen> createState() => _BuyerRequestDetailScreenState();
}

class _BuyerRequestDetailScreenState extends State<BuyerRequestDetailScreen> {
  final BuyerRequestService _service = BuyerRequestService();
  BuyerRequest? _request;
  List<BuyerRequestOffer> _offers = const [];
  List<BuyerRequestView> _views = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _unlockedSellerContacts = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.getDetail(widget.requestId);
      final offers = await _service.listOffers(widget.requestId);
      final views = r.isOwner ? await _service.listViews(widget.requestId) : const <BuyerRequestView>[];
      if (r.canOffer == false && !r.isOwner) {
        // Still track a detail view for sellers who open the page.
      }
      if (!r.isOwner) {
        await _service.trackView(widget.requestId);
      }
      if (!mounted) return;
      setState(() {
        _request = r;
        _offers = offers.items;
        _views = views;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _contactSeller(BuyerRequestOffer offer) async {
    if (!_unlockedSellerContacts.contains(offer.sellerUid)) {
      final watch = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('unlock_contact')),
          content: Text(context.tr('unlock_contact_ad_msg')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('watch_ad')),
            ),
          ],
        ),
      );
      if (watch != true || !mounted) return;
      final rewarded = await RewardedAdService.showRewarded();
      if (!mounted) return;
      if (!rewarded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('watch_ad_to_continue'))),
        );
        return;
      }
      setState(() => _unlockedSellerContacts.add(offer.sellerUid));
    }
    try {
      final data = await _service.sellerContact(widget.requestId, offer.sellerUid);
      final link = data['deepLink'] as String?;
      if (link != null) {
        await _service.recordWhatsappClick(widget.requestId, offer.sellerUid);
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seller has not enabled WhatsApp contact')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _submitOffer() async {
    final priceCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price (TZS)'), keyboardType: TextInputType.number),
            TextField(controller: messageCtrl, decoration: const InputDecoration(labelText: 'Message')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (result != true) return;
    try {
      await _service.createOffer(widget.requestId, {
        'price': int.tryParse(priceCtrl.text.trim()) ?? 0,
        'message': messageCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer submitted')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _request == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(_error ?? 'Not found')));
    }
    final r = _request!;
    return Scaffold(
      appBar: AppBar(title: Text(r.title)),
      floatingActionButton: r.canOffer
          ? FloatingActionButton.extended(onPressed: _submitOffer, label: const Text('Submit offer'), icon: const Icon(Icons.send))
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (r.images.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: r.images.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Image.network(r.images[i], width: 220, fit: BoxFit.cover),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(r.description),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            Chip(label: Text('TZS ${r.minBudget}-${r.maxBudget}')),
            if (r.location.isNotEmpty) Chip(label: Text(r.location)),
            Chip(label: Text('${r.offersCount}/${r.offerLimit} offers')),
            Chip(label: Text('${r.viewCount} views')),
            Chip(label: Text(r.status)),
          ]),
          if (r.requirements.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Requirements: ${r.requirements}'),
          ],
          if (r.isOwner) ...[
            const SizedBox(height: 16),
            const Text('Sellers who opened this request', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._views.map((v) => ListTile(
                  leading: CircleAvatar(child: Text(v.sellerName.isNotEmpty ? v.sellerName[0] : '?')),
                  title: Text(v.sellerName),
                  subtitle: Text('${v.sellerStoreName} • ${v.viewCount} views'),
                  trailing: v.sellerKycApproved ? const Icon(Icons.verified, color: Colors.blue) : null,
                )),
            const SizedBox(height: 16),
            const Text('Offers', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._offers.map((o) => Card(
                  child: ListTile(
                    title: Text('${o.sellerStoreName.isNotEmpty ? o.sellerStoreName : o.sellerName} - TZS ${o.price}'),
                    subtitle: Text(o.message),
                    trailing: r.canClose
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () async {
                                  await _service.decideOffer(widget.requestId, o.id, 'accept');
                                  await _load();
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () async {
                                  await _service.decideOffer(widget.requestId, o.id, 'decline');
                                  await _load();
                                },
                              ),
                              if (o.sellerWhatsappEnabled)
                                IconButton(
                                  icon: const Icon(Icons.chat, color: Colors.green),
                                  onPressed: () => _contactSeller(o),
                                ),
                            ],
                          )
                        : (o.sellerWhatsappEnabled
                            ? IconButton(icon: const Icon(Icons.chat, color: Colors.green), onPressed: () => _contactSeller(o))
                            : null),
                  ),
                )),
            if (r.canClose)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton.tonal(onPressed: () async {
                  await _service.close(widget.requestId);
                  await _load();
                }, child: const Text('Close request')),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonal(
                onPressed: () => context.push(AppRoutes.postBuyerRequest),
                child: const Text('Create similar request'),
              ),
            ),
            if (r.canExtend)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonal(onPressed: () async {
                  await _service.extend(widget.requestId);
                  await _load();
                }, child: const Text('Extend request')),
              ),
            if (r.canReopen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonal(onPressed: () async {
                  await _service.reopen(widget.requestId);
                  await _load();
                }, child: const Text('Reopen request')),
              ),
          ] else ...[
            if (r.hasOffered)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('You have already submitted an offer', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            if (r.offerBlockReason != null && !r.canOffer)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Cannot offer: ${r.offerBlockReason}'),
              ),
          ],
        ],
      ),
    );
  }
}
