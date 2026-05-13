import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../services/live_gift_service.dart';
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';

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
    final bal = await _service.getPremiumCoins();
    if (mounted) setState(() => _coins = bal);
  }

  Future<void> _buy(int totalCoins, int price) async {
    setState(() => _buying = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final phone = userDoc.data()?['phone'] as String?;

      if (phone == null || phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('add_phone_first'))),
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
            SnackBar(content: Text(context.tr('failed_payment_init'))),
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
        ).showSnackBar(SnackBar(content: Text("${context.tr('error')}: $e")));
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
                      '$totalCoins ${context.tr('coins_added')}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: Text(context.tr('complete_purchase')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('payment_prompt_sent'),
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
      appBar: AppBar(title: Text(context.tr('buy_coins'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                color: Colors.amber[50],
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    MediaQuery.of(context).padding.bottom + 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: Colors.amber,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${context.tr("your_balance")} $_coins ${context.tr("coins")}',
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
                                '+${p['bonus']} ${context.tr("bonus")}',
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
      ),
    );
  }
}
