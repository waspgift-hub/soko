import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/product_model.dart';
import 'follow_service.dart';
import 'recently_viewed_service.dart';

/// Real-signal suggestions: sellers behind recently viewed and wishlisted
/// products, excluding self and already-followed accounts. Never random.
class SuggestionService {
  final FollowService _follow = FollowService();

  Future<List<Map<String, dynamic>>> suggestSellers({int limit = 5}) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isEmpty) return [];
    try {
      final viewedIds = await RecentlyViewedService.instance.getIds();
      if (viewedIds.isEmpty) return [];
      final products =
          await RecentlyViewedService.instance.loadProducts(viewedIds);
      final followed = await _follow.getFollowing(me).first;
      final followedIds =
          followed.map((e) => (e['id'] ?? e['userId']).toString()).toSet();
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final Product p in products) {
        if (p.sellerId.isEmpty || p.sellerId == me) continue;
        if (followedIds.contains(p.sellerId)) continue;
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

  Future<Map<String, String>> sellerNames(Set<String> sellerIds) async {
    final map = <String, String>{};
    for (final id in sellerIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(id)
            .get();
        final data = doc.data();
        if (data != null) {
          map[id] = (data['displayName'] ?? data['name'] ?? 'Member').toString();
        }
      } catch (_) {}
    }
    return map;
  }
}
