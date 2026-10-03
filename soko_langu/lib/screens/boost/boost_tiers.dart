import 'package:flutter/material.dart';

/// Commercial + visual definition of a boost package.
///
/// Prices and durations mirror what `/api/boost-product` bills, so the numbers
/// the seller reads on screen are the numbers they are charged. Every derived
/// figure (reach, views, chats, savings) is computed from the tier instead of
/// being hand-written, which keeps a longer package always reading as a bigger
/// win and stops the copy from drifting away from the price.
class BoostTier {
  final String key;
  final int price;
  final int days;
  final IconData icon;
  final Color accent;
  final List<Color> gradient;

  /// Average impressions a boosted listing earns per day. Bronze is the
  /// reference package; the wider packages buy more of the same inventory.
  final int dailyReach;

  /// Translation keys describing what this package includes, weakest first.
  final List<String> featureKeys;

  final bool popular;

  /// Price of one Bronze day. Every package is priced against it, which is what
  /// makes the "you save" claim on the wider bundles verifiable rather than
  /// invented marketing.
  static const int _dayRate = 1500 ~/ 3;

  const BoostTier({
    required this.key,
    required this.price,
    required this.days,
    required this.icon,
    required this.accent,
    required this.gradient,
    required this.dailyReach,
    required this.featureKeys,
    this.popular = false,
  });

  /// Cost per day, the number that makes a longer bundle look rational.
  double get pricePerDay => price / days;

  /// Cost of buying the same number of days at the Bronze day rate. Bronze
  /// *is* the day rate, so it comes out at zero and shows no saving tag.
  int get savingsVsDayRate => (_dayRate * days - price).round();

  /// Fraction saved against the Bronze day rate, 0..1.
  double get savingsPercent => savingsVsDayRate / (_dayRate * days);

  /// Impressions a full package is expected to earn.
  int get impressions => dailyReach * days;

  /// Roughly a third of impressions end in an open listing page.
  int get views => (impressions * 0.36).round();

  /// A small slice of those views become buyer conversations.
  int get buyerChats => (impressions * 0.04).round();

  /// Views an unboosted listing earns over the same span, for the
  /// boosted-vs-normal comparison bar.
  int get normalViews => (views / 2.4).round();

  /// The view multiplier a boost buys over normal organic reach.
  String get viewMultiplier => (views / normalViews).toStringAsFixed(1);

  static const List<BoostTier> all = [
    BoostTier(
      key: 'bronze',
      price: 1500,
      days: 3,
      icon: Icons.bolt_rounded,
      accent: Color(0xFF8E8E93),
      gradient: [Color(0xFF6E6E73), Color(0xFF3A3A3D)],
      dailyReach: 1200,
      featureKeys: ['boost_why_1', 'boost_why_2', 'boost_why_3'],
    ),
    BoostTier(
      key: 'silver',
      price: 3000,
      days: 7,
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFF00C853),
      gradient: [Color(0xFF00E676), Color(0xFF00A844)],
      dailyReach: 1800,
      featureKeys: ['boost_why_1', 'boost_why_2', 'boost_why_3', 'boost_why_4'],
      popular: true,
    ),
    BoostTier(
      key: 'gold',
      price: 10000,
      days: 30,
      icon: Icons.workspace_premium_rounded,
      accent: Color(0xFFF59E0B),
      gradient: [Color(0xFFFFC93C), Color(0xFFD98A00)],
      dailyReach: 2300,
      featureKeys: [
        'boost_why_1',
        'boost_why_2',
        'boost_why_3',
        'boost_why_4',
        'boost_why_5',
        'boost_why_6',
      ],
    ),
  ];

  static const String silverKey = 'silver';

  static const String goldKey = 'gold';

  static BoostTier byKey(String key) => all.firstWhere((t) => t.key == key, orElse: () => all[1]);
}

/// Everything a single boost buys, keyed for [trParams]-style lookup. Used by
/// the value-prop grid above the packages, where the seller sees the full menu
/// before choosing a tier.
const boostValueProps = <(IconData, String)>[
  (Icons.search_rounded, 'boost_why_1'),
  (Icons.verified_rounded, 'boost_why_2'),
  (Icons.view_carousel_rounded, 'boost_why_3'),
  (Icons.category_rounded, 'boost_why_4'),
  (Icons.ios_share_rounded, 'boost_why_5'),
  (Icons.support_agent_rounded, 'boost_why_6'),
];

/// Mobile-money rails the boost endpoint accepts, each carrying its operator
/// brand colour so the seller recognises their own network at a glance. The
/// `key` values are the identifiers `/api/boost-product` expects as `provider`,
/// so adding one here is a server-side change too.
const boostProviders = <(String, String, Color)>[
  ('mpesa', 'M-Pesa', Color(0xFFE60000)),
  ('tigo', 'Tigo Pesa', Color(0xFF1B3A93)),
  ('airtel', 'Airtel Money', Color(0xFFE4002B)),
  ('halopesa', 'HaloPesa', Color(0xFF5C2D91)),
  ('ezy', 'EzyPesa', Color(0xFF00A651)),
  ('crdb', 'CRDB', Color(0xFF00539F)),
];

/// Abbreviates a projected figure. `1296` reads as noise next to an estimate,
/// so thousands collapse to one decimal (`1.3K`) and very large ones drop the
/// decimal entirely (`69K`). Shared so the stat tiles and the comparison bars
/// never disagree about how a number should read.
String formatBoostCount(int value) {
  if (value < 1000) return '$value';
  final k = value / 1000;
  return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}K';
}
