import 'package:flutter/material.dart';

/// Canonical icon names for marketplace categories. Stored in seeds and
/// used as the fallback when the server sends no `iconUrl` — never emoji.
class CategoryIconNames {
  static const package = 'package';
  static const smartphone = 'smartphone';
  static const checkroom = 'checkroom';
  static const chair = 'chair';
  static const childCare = 'child_care';
  static const spa = 'spa';
  static const car = 'car';
  static const soccer = 'soccer';
  static const book = 'book';
  static const fastfood = 'fastfood';
  static const grocery = 'grocery';
  static const handyman = 'handyman';
  static const factory = 'factory';
  static const diamond = 'diamond';
  static const gift = 'gift';
  static const shoppingBag = 'shopping_bag';
  static const toys = 'toys';
}

/// Rounded solid Material icon for a category.
///
/// Resolves by stable [slug] first so rendering never depends on what the
/// server puts in `icon`. Legacy emoji glyphs (old Firestore docs) still
/// map correctly; URLs and unknown values fall back to the package icon.
IconData categoryIconFor({String? icon, String? slug, String? name}) {
  final key = (slug ?? '').toLowerCase().trim();
  if (key.isNotEmpty) {
    final bySlug = _iconForKey(key);
    if (bySlug != null) return bySlug;
  }
  final raw = (icon ?? '').trim();
  if (raw.isNotEmpty) {
    // Server icon URLs are rendered as images by the card, not as icons.
    if (raw.startsWith('http')) return Icons.inventory_2_rounded;
    final byName = _iconForKey(raw.toLowerCase());
    if (byName != null) return byName;
    final legacy = _legacyEmojiIcon(raw);
    if (legacy != null) return legacy;
  }
  final byName = _iconForKey((name ?? '').toLowerCase().trim());
  if (byName != null) return byName;
  return Icons.inventory_2_rounded;
}

IconData? _iconForKey(String key) {
  switch (key) {
    case 'electronics':
    case 'smartphone':
    case 'phones':
      return Icons.smartphone_rounded;
    case 'fashion':
    case 'checkroom':
    case 'mens':
    case 'womens':
      return Icons.checkroom_rounded;
    case 'shoes':
      return Icons.ice_skating_rounded;
    case 'home_garden':
    case 'home':
    case 'chair':
    case 'furniture':
      return Icons.chair_rounded;
    case 'kids':
    case 'maternal':
    case 'child_care':
    case 'baby':
      return Icons.child_care_rounded;
    case 'toys':
      return Icons.toys_rounded;
    case 'health_beauty':
    case 'health':
    case 'beauty':
    case 'spa':
      return Icons.spa_rounded;
    case 'automotive':
    case 'car':
    case 'cars':
      return Icons.directions_car_rounded;
    case 'sports':
    case 'soccer':
    case 'fitness':
      return Icons.sports_soccer_rounded;
    case 'books':
    case 'book':
    case 'media':
      return Icons.menu_book_rounded;
    case 'food':
    case 'fastfood':
    case 'groceries':
      return Icons.fastfood_rounded;
    case 'grocery':
    case 'beverages':
      return Icons.local_grocery_store_rounded;
    case 'services':
    case 'handyman':
    case 'repair':
      return Icons.handyman_rounded;
    case 'business':
    case 'factory':
      return Icons.factory_rounded;
    case 'jewelry':
    case 'diamond':
      return Icons.diamond_rounded;
    case 'gifts':
    case 'gift':
      return Icons.card_giftcard_rounded;
    case 'shopping':
    case 'shopping_bag':
      return Icons.shopping_bag_rounded;
    case 'package':
    case 'others':
    case 'other':
      return Icons.inventory_2_rounded;
    default:
      return null;
  }
}

// Old Firestore docs store an emoji glyph in `icon`; keep rendering them
// until the backfill rewrites those rows to canonical names.
IconData? _legacyEmojiIcon(String glyph) {
  switch (glyph) {
    case '📦':
      return Icons.inventory_2_rounded;
    case '📱':
      return Icons.smartphone_rounded;
    case '👗':
    case '👕':
      return Icons.checkroom_rounded;
    case '👟':
      return Icons.ice_skating_rounded;
    case '💄':
      return Icons.spa_rounded;
    case '🛋️':
    case '🪑':
      return Icons.chair_rounded;
    case '⚽':
    case '🏀':
      return Icons.sports_soccer_rounded;
    case '📚':
      return Icons.menu_book_rounded;
    case '🎁':
      return Icons.card_giftcard_rounded;
    case '💎':
      return Icons.diamond_rounded;
    case '🔧':
      return Icons.handyman_rounded;
    case '🍎':
      return Icons.local_grocery_store_rounded;
    case '🛒':
      return Icons.shopping_bag_rounded;
    case '🚗':
      return Icons.directions_car_rounded;
    case '🏭':
      return Icons.factory_rounded;
    case '🍔':
    case '🥦':
      return Icons.fastfood_rounded;
    case '👶':
    case '🧸':
      return Icons.child_care_rounded;
    case '🏠':
      return Icons.chair_rounded;
    default:
      return null;
  }
}
