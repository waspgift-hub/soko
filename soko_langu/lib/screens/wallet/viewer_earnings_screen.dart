import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/viewer_earnings_service.dart';
import '../../models/live_gift.dart';
import '../../extensions/context_tr.dart';

class ViewerEarningsScreen extends StatefulWidget {
  const ViewerEarningsScreen({super.key});

  @override
  State<ViewerEarningsScreen> createState() => _ViewerEarningsScreenState();
}

class _ViewerEarningsScreenState extends State<ViewerEarningsScreen> {
  final _earnService = ViewerEarningsService();
  RewardedAd? _rewardedAd;
  bool _loadingAd = false;
  bool _crediting = false;
  int _todayCount = 0;
  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;

  static const int maxDailyAds = 20;
  static const int cooldownSeconds = 60;
  static const int softCoinsPerAd = 5;

  @override
  void initState() {
    super.initState();
    _loadTodayCount();
    _loadLastAdTime();
    _loadAd();
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTodayCount() async {
    final count = await _earnService.getDailyAdCount();
    if (mounted) setState(() => _todayCount = count);
  }

  Future<void> _loadLastAdTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('last_ad_time');
    if (ts != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(ts);
      if (mounted) _checkCooldown(last);
    }
  }

  void _checkCooldown(DateTime lastTime) {
    final elapsed = DateTime.now().difference(lastTime).inSeconds;
    if (elapsed < cooldownSeconds) {
      _cooldownRemaining = cooldownSeconds - elapsed;
      _startCooldown();
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldownRemaining--;
        if (_cooldownRemaining <= 0) {
          _cooldownRemaining = 0;
          t.cancel();
        }
      });
    });
  }

  Future<void> _loadAd() async {
    if (_loadingAd) return;
    if (_rewardedAd != null) return;
    setState(() => _loadingAd = true);

    await RewardedAd.load(
      adUnitId: ViewerEarningsService.adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          if (mounted) setState(() => _loadingAd = false);
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          if (mounted) setState(() => _loadingAd = false);
        },
      ),
    );
  }

  Future<void> _watchAd() async {
    if (_crediting) return;
    if (_todayCount >= maxDailyAds) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('daily_limit_reached'))),
        );
      }
      return;
    }
    if (_cooldownRemaining > 0) return;

    if (_rewardedAd == null) {
      await _loadAd();
      if (_rewardedAd == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr('ad_not_ready'))));
        }
        return;
      }
    }

    final ad = _rewardedAd!;
    _rewardedAd = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.tr('ad_failed'))));
        }
        _loadAd();
      },
    );

    await ad.show(
      onUserEarnedReward: (ad, reward) {
        _creditCoins();
      },
    );
  }

  Future<void> _creditCoins() async {
    setState(() => _crediting = true);
    try {
      await _earnService.creditAdView(coins: softCoinsPerAd);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_ad_time', DateTime.now().millisecondsSinceEpoch);
      if (mounted) {
        setState(() {
          _todayCount++;
          _cooldownRemaining = cooldownSeconds;
        });
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('earned_coins')} +$softCoinsPerAd'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('earn_failed')}: $e')),
        );
      }
    }
    if (mounted) {
      setState(() => _crediting = false);
      _loadAd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('earn_coins'))),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots(),
                builder: (ctx, snap) {
                  final data = snap.data?.data() as Map<String, dynamic>? ?? {};
                  final softCoins = (data['softCoins'] ?? 0) as int;
                  final premiumCoins = (data['coins'] ?? 0) as int;
                  final softTzs = softCoins * LiveGift.tzsPerSoftCoin;
                  final premiumTzs = premiumCoins * LiveGift.tzsPerPremiumCoin;

                  return Card(
                    color: Colors.green[50],
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: Colors.green,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('your_coins'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _coinBadge(
                                '🪙',
                                context.tr('soft_coins'),
                                '$softCoins',
                                '≈ TZS $softTzs',
                                Colors.green,
                              ),
                              _coinBadge(
                                '💎',
                                context.tr('premium_coins'),
                                '$premiumCoins',
                                '≈ TZS $premiumTzs',
                                Colors.amber,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // ── Watch Ad Section ──
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.tr('today'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '$_todayCount / $maxDailyAds',
                            style: TextStyle(
                              color: _todayCount >= maxDailyAds
                                  ? Colors.red
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: _todayCount / maxDailyAds,
                        backgroundColor: Colors.grey[200],
                        color: _todayCount >= maxDailyAds
                            ? Colors.red
                            : Colors.green,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${context.tr('earn_per_ad')}: +$softCoinsPerAd ${context.tr('soft_coins').toLowerCase()}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed:
                              (_crediting ||
                                  _loadingAd ||
                                  _todayCount >= maxDailyAds ||
                                  _cooldownRemaining > 0)
                              ? null
                              : _watchAd,
                          icon: _crediting || _loadingAd
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_circle_fill),
                          label: Text(
                            _crediting
                                ? context.tr('crediting')
                                : _loadingAd
                                ? context.tr('loading_ad')
                                : _cooldownRemaining > 0
                                ? '${context.tr('cooldown')} ${_cooldownRemaining}s'
                                : context.tr('watch_ad'),
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Soft coins info ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Soft coins are for sending gifts in live streams only. They cannot be cashed out.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coinBadge(
    String emoji,
    String label,
    String amount,
    String tzsValue,
    Color color,
  ) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 32)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(
          amount,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(tzsValue, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
