import 'package:flutter/material.dart';

/// Commercial + visual definition of a boost package.
///
/// Prices and durations mirror what `/api/boost-product` bills, so the numbers
/// the seller reads on screen are the numbers they are charged. No reach,
/// view or saving figures are derived anywhere: any projection would be
/// invented marketing and would drift from the real price.
class BoostTier {
  final String key;
  final int price;
  final int days;
  final IconData icon;
  final Color accent;
  final List<Color> gradient;

  /// Translation keys describing what this package includes, weakest first.
  final List<String> featureKeys;

  final bool popular;

  const BoostTier({
    required this.key,
    required this.price,
    required this.days,
    required this.icon,
    required this.accent,
    required this.gradient,
    required this.featureKeys,
    this.popular = false,
  });

  static const List<BoostTier> all = [
    BoostTier(
      key: 'bronze',
      price: 1500,
      days: 3,
      icon: Icons.bolt_rounded,
      accent: Color(0xFF8E8E93),
      gradient: [Color(0xFF6E6E73), Color(0xFF3A3A3D)],
      featureKeys: ['boost_why_1', 'boost_why_2', 'boost_why_3'],
    ),
    BoostTier(
      key: 'silver',
      price: 3000,
      days: 7,
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFF00C853),
      gradient: [Color(0xFF00E676), Color(0xFF00A844)],
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

/// Rails `/api/boost-product` can settle a charge on. The screen no longer
/// asks the seller to choose — provider and method are fixed internal
/// defaults (`mpesa` + USSD push) that satisfy the server payload.
enum BoostPayMethod { ussd, billpay }

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
