class LiveGift {
  final String id;
  final String emoji;
  final String name;
  final int coinCost;

  const LiveGift({
    required this.id,
    required this.emoji,
    required this.name,
    required this.coinCost,
  });

  static const List<LiveGift> gifts = [
    LiveGift(id: 'rose', emoji: '🌹', name: 'Rose', coinCost: 10),
    LiveGift(id: 'teddy', emoji: '🧸', name: 'Teddy Bear', coinCost: 50),
    LiveGift(id: 'crown', emoji: '👑', name: 'Crown', coinCost: 200),
    LiveGift(id: 'lion', emoji: '🦁', name: 'Lion', coinCost: 500),
    LiveGift(id: 'universe', emoji: '🌌', name: 'Universe', coinCost: 2000),
    LiveGift(id: 'galaxy', emoji: '🌠', name: 'Galaxy', coinCost: 5000),
  ];

  double get tzsValue => coinCost * 5; // 1 coin = TZS 5
}
