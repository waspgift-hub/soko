class LiveGift {
  final String id;
  final String emoji;
  final String name;
  final int coinCost;
  final bool isPremium;

  const LiveGift({
    required this.id,
    required this.emoji,
    required this.name,
    required this.coinCost,
    this.isPremium = false,
  });

  static const List<LiveGift> gifts = [
    LiveGift(id: 'rose', emoji: '🌹', name: 'Rose', coinCost: 10),
    LiveGift(id: 'teddy', emoji: '🧸', name: 'Teddy Bear', coinCost: 50),
    LiveGift(id: 'crown', emoji: '👑', name: 'Crown', coinCost: 200),
    LiveGift(id: 'lion', emoji: '🦁', name: 'Lion', coinCost: 500),
  ];

  static const List<LiveGift> premiumGifts = [
    LiveGift(
      id: 'universe',
      emoji: '🌌',
      name: 'Universe',
      coinCost: 1000,
      isPremium: true,
    ),
    LiveGift(
      id: 'galaxy',
      emoji: '🌠',
      name: 'Galaxy',
      coinCost: 3000,
      isPremium: true,
    ),
    LiveGift(
      id: 'diamond',
      emoji: '💎',
      name: 'Diamond',
      coinCost: 5000,
      isPremium: true,
    ),
    LiveGift(
      id: 'phoenix',
      emoji: '🦅',
      name: 'Phoenix',
      coinCost: 10000,
      isPremium: true,
    ),
  ];

  static int get tzsPerPremiumCoin => 5;
  static int get tzsPerSoftCoin => 1;

  int valueInTzs(int coins, {bool isPremiumCoin = false}) =>
      coins * (isPremiumCoin ? tzsPerPremiumCoin : tzsPerSoftCoin);
}
