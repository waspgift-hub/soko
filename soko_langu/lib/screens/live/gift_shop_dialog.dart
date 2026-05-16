import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/live_gift.dart';
import '../../services/live_gift_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';

class GiftShopDialog extends StatefulWidget {
  final String streamerId;
  final String streamId;

  const GiftShopDialog({
    super.key,
    required this.streamerId,
    required this.streamId,
  });

  @override
  State<GiftShopDialog> createState() => _GiftShopDialogState();
}

class _GiftShopDialogState extends State<GiftShopDialog> {
  final _service = LiveGiftService();
  int _premiumCoins = 0;
  int _softCoins = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    final premium = await _service.getPremiumCoins();
    final soft = await _service.getSoftCoins();
    if (mounted) {
      setState(() {
        _premiumCoins = premium;
        _softCoins = soft;
      });
    }
  }

  bool _canAfford(LiveGift gift) {
    if (gift.isPremium) return _premiumCoins >= gift.coinCost;
    return (_premiumCoins + _softCoins) >= gift.coinCost;
  }

  Future<void> _sendGift(LiveGift gift) async {
    if (!_canAfford(gift)) {
      Navigator.pop(context);
      context.push(AppRoutes.buyCoins);
      return;
    }

    setState(() => _sending = true);
    final ok = await _service.sendGift(
      streamerId: widget.streamerId,
      streamId: widget.streamId,
      gift: gift,
    );

    if (mounted) {
      if (ok) {
        Navigator.pop(context);
        _loadCoins();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${context.tr('sent')} ${gift.emoji} ${gift.name}!"),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header with balances ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('gift_shop'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    context.push(AppRoutes.buyCoins);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_premiumCoins',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '🪙$_softCoins',
                          style: TextStyle(
                            color: Colors.green[600],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('buy'),
                          style: TextStyle(
                            color: Colors.amber[800],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Regular Gifts ──
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('regular_gifts'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: LiveGift.gifts.length,
              itemBuilder: (ctx, i) {
                final gift = LiveGift.gifts[i];
                final canAfford = _canAfford(gift);
                return GestureDetector(
                  onTap: _sending ? null : () => _sendGift(gift),
                  child: Opacity(
                    opacity: canAfford ? 1 : 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: canAfford ? Colors.grey[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            gift.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            gift.name,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '${gift.coinCost} coins',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.amber[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // ── Premium Gifts ──
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    context.tr('premium_gifts'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.amber[800],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: LiveGift.premiumGifts.length,
              itemBuilder: (ctx, i) {
                final gift = LiveGift.premiumGifts[i];
                final canAfford = _premiumCoins >= gift.coinCost;
                return GestureDetector(
                  onTap: _sending ? null : () => _sendGift(gift),
                  child: Opacity(
                    opacity: canAfford ? 1 : 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: canAfford
                            ? const LinearGradient(
                                colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: canAfford ? null : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: canAfford
                              ? Colors.amber[300]!
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            gift.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            gift.name,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 10,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${gift.coinCost}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.amber[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
