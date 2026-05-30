import 'package:shared_preferences/shared_preferences.dart';

class WishlistService {
  static const _key = 'wishlist_ids';

  Future<List<String>> getWishlist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<bool> isFavorite(String productId) async {
    final ids = await getWishlist();
    return ids.contains(productId);
  }

  Future<void> toggle(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    if (ids.contains(productId)) {
      ids.remove(productId);
    } else {
      ids.add(productId);
    }
    await prefs.setStringList(_key, ids);
  }

  Future<void> add(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    if (!ids.contains(productId)) {
      ids.add(productId);
      await prefs.setStringList(_key, ids);
    }
  }

  Future<void> remove(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    ids.remove(productId);
    await prefs.setStringList(_key, ids);
  }
}
