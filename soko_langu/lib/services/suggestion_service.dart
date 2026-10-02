import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/product_model.dart';
import 'recently_viewed_service.dart';

/// Real-signal suggestions: sellers behind recently viewed and wishlisted
/// products, excluding self and blocked accounts. Never random.
class SuggestionService {
  Future<List<Map<String, dynamic>>> suggestSellers({int limit = 5}) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isEmpty) return [];
    try {
      final viewedIds = await RecentlyViewedService.instance.getIds();
      if (viewedIds.isEmpty) return [];
      final products =
          await RecentlyViewedService.instance.loadProducts(viewedIds);
      final blocked = await _blockedIds(me);
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final Product p in products) {
        if (p.sellerId.isEmpty || p.sellerId == me) continue;
        if (blocked.contains(p.sellerId)) continue;
        if (!seen.add(p.sellerId)) continue;
        out.add({
          'sellerId': p.sellerId,
          'sellerName': p.sellerName,
          'productName': p.name,
          'productImage':
              p.images.isNotEmpty ? p.images.first : null,
        });
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<Set<String>> _blockedIds(String me) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .get();
      final list = doc.data()?['blockedUsers'];
      if (list is List) return list.map((e) => e.toString()).toSet();
    } catch (_) {}
    return {};
  }

  /// Display names for other users.
  ///
  /// Reads `userPublic/{uid}`, NOT `users/{uid}`. The private `users` doc holds
  /// contact details, KYC state and balances, and Firestore rules now restrict
  /// it to the owner; the projection carries only display data and is safe to
  /// read for anyone.
  Future<Map<String, String>> sellerNames(Set<String> sellerIds) async {
    final map = <String, String>{};
    for (final id in sellerIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('userPublic')
            .doc(id)
            .get();
        final data = doc.data();
        if (data != null) {
          map[id] = (data['displayName'] ?? 'Member').toString();
        }
      } catch (_) {}
    }
    return map;
  }
}
