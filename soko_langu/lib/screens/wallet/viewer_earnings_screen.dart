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
  int _totalCount = 0;
  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;

  static const int maxTotalAds = 30;
  static const int cooldownSeconds = 60;
  static const int viewerReward = 5;
  static const int adminReward = 15;

  @override
  void initState() {
    super.initState();
    _loadTotalCount();
    _loadLastAdTime();
    _loadAd();
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTotalCount() async {
    final count = await _earnService.getTotalAdCount();
    if (mounted) setState(() => _totalCount = count);
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
      if (!mounted) { t.cancel(); return; }
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
    if (_totalCount >= maxTotalAds) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('total_limit_reached'))),
        );
      }
      return;
    }
    if (_cooldownRemaining > 0) return;

    if (_rewardedAd == null) {
      await _loadAd();
      if (_rewardedAd == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('ad_not_ready'))),
          );
        }
        return;
      }
    }

    final ad = _rewardedAd!;
    _rewardedAd = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadAd();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('ad_failed'))),
          );
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
      await _earnService.creditAdView(
        viewerCoins: viewerReward,
        adminCoins: adminReward,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_ad_time', DateTime.now().millisecondsSinceEpoch);
      if (mounted) {
        setState(() {
          _totalCount++;
          _cooldownRemaining = cooldownSeconds;
        });
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('earned_coins')} +$viewerReward'),
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
    final canWatch = _totalCount < maxTotalAds;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('earn_coins'))),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
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
                          const Icon(Icons.monetization_on, color: Colors.green, size: 48),
                          const SizedBox(height: 8),
                          Text(context.tr('your_coins'), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _coinBadge('🪙', context.tr('soft_coins'), '$softCoins', '≈ TZS $softTzs', Colors.green),
                              _coinBadge('💎', context.tr('premium_coins'), '$premiumCoins', '≈ TZS $premiumTzs', Colors.amber),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.tr('total_ads_watched'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('$_totalCount / $maxTotalAds', style: TextStyle(color: canWatch ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: _totalCount / maxTotalAds,
                          backgroundColor: Colors.grey[200],
                          color: canWatch ? Colors.green : Colors.red,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber[200]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.tr('ad_revenue_split'),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _adButton(
                          label: context.tr('watch_ad'),
                          subtitle: '+$viewerReward ${context.tr('soft_coins').toLowerCase()} (50%)',
                          color: const Color(0xFF2D6A4F),
                          icon: Icons.play_circle_outline,
                          canWatch: canWatch,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adButton({
    required String label,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool canWatch,
  }) {
    final disabled = _crediting || _loadingAd || !canWatch || _cooldownRemaining > 0;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: disabled ? null : () => _watchAd(),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _crediting || _loadingAd
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  _crediting ? context.tr('crediting')
                  : _loadingAd ? context.tr('loading_ad')
                  : _cooldownRemaining > 0 ? '${context.tr('cooldown')} ${_cooldownRemaining}s'
                  : label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _coinBadge(String emoji, String label, String amount, String tzsValue, Color color) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 32)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(amount, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(tzsValue, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }
}
