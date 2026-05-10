import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../models/live_gift.dart';
import '../../services/live_gift_service.dart';
import '../../services/api_config.dart';

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
  int _coins = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    final bal = await _service.getCoinBalance();
    if (mounted) setState(() => _coins = bal);
  }

  Future<void> _sendGift(LiveGift gift) async {
    if (_coins < gift.coinCost) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BuyCoinsScreen()),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent ${gift.emoji} ${gift.name}!'),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Gifts',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BuyCoinsScreen()),
                  );
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
                        '$_coins',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Buy',
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: LiveGift.gifts.length,
            itemBuilder: (ctx, i) {
              final gift = LiveGift.gifts[i];
              final canAfford = _coins >= gift.coinCost;
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
                        Text(gift.emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 4),
                        Text(
                          gift.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          '${gift.coinCost} coins',
                          style: TextStyle(
                            fontSize: 10,
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
        ],
      ),
    );
  }
}

class BuyCoinsScreen extends StatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends State<BuyCoinsScreen> {
  final _service = LiveGiftService();
  int _coins = 0;
  bool _buying = false;

  static final packages = [
    {'coins': 100, 'price': 500},
    {'coins': 500, 'price': 2000},
    {'coins': 1000, 'price': 3500, 'bonus': 100},
    {'coins': 5000, 'price': 15000, 'bonus': 1000},
  ];

  @override
  void initState() {
    super.initState();
    _loadCoins();
  }

  Future<void> _loadCoins() async {
    final bal = await _service.getCoinBalance();
    if (mounted) setState(() => _coins = bal);
  }

  Future<void> _buy(int totalCoins, int price) async {
    setState(() => _buying = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // get user phone from firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final phone = userDoc.data()?['phone'] as String?;

      if (phone == null || phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please add your phone number in Profile settings first',
              ),
            ),
          );
        }
        setState(() => _buying = false);
        return;
      }

      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/buy-coins'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'coins': totalCoins,
          'price': price,
          'phone': phone,
          'userId': user.uid,
        }),
      );

      if (resp.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to initiate payment')),
          );
        }
        setState(() => _buying = false);
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final orderId = data['order_id'] as String?;

      if (orderId == null) {
        setState(() => _buying = false);
        return;
      }

      if (!mounted) return;
      await _showPaymentDialog(orderId, totalCoins);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _showPaymentDialog(String orderId, int totalCoins) async {
    final completer = Completer<void>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .doc(orderId)
              .snapshots(),
          builder: (ctx, snap) {
            final status = snap.data?.get('status') as String?;

            if (status == 'completed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadCoins();
                completer.complete();
              });
              return AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$totalCoins coins added!',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('Complete Purchase'),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Payment prompt sent to your phone.\n'
                    'Check M-Pesa, Airtel Money, or Mixx\n'
                    'and enter your PIN to complete.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    completer.complete();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Buy Coins')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Your Balance: $_coins coins',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: packages.length,
                itemBuilder: (ctx, i) {
                  final p = packages[i];
                  final coins = (p['coins'] ?? 0) + (p['bonus'] ?? 0);
                  final price = p['price'] ?? 0;
                  return GestureDetector(
                    onTap: _buying ? null : () => _buy(coins, price),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber[200]!,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withAlpha(25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$coins',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          if (p.containsKey('bonus'))
                            Text(
                              '+${p['bonus']} bonus',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'TZS $price',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
