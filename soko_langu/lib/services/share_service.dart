import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

import 'deep_link_parser.dart';

/// Centralized sharing helpers — single place for share text generation and
/// native share sheet invocation. No fake UI, only [SharePlus].
class ShareService {
  ShareService._();
  static final ShareService instance = ShareService._();

  /// Share a product. Generates localized text but uses the canonical URL.
  Future<void> shareProduct({
    required String productId,
    required String productName,
    required double price,
    String currency = 'TZS',
    String? locale,
  }) async {
    final url = DeepLinkParser.productUrl(productId);
    final priceStr = _formatPrice(price, currency);
    // Swahili default, English fallback already handled by caller if needed
    final text = '$productName - $priceStr\nInapatikana Soko Vibe.\n$url';
    await _share(text);
    _track('product_shared');
  }

  Future<void> shareSeller({
    required String sellerId,
    required String sellerName,
  }) async {
    final url = DeepLinkParser.sellerUrl(sellerId);
    final text = 'Angalia bidhaa za $sellerName kwenye Soko Vibe.\n$url';
    await _share(text);
    _track('seller_shared');
  }

  Future<void> shareProfile({
    required String userId,
    required String displayName,
    String? username,
  }) async {
    final id = username != null && username.isNotEmpty ? username : userId;
    final url = DeepLinkParser.profileUrl(id);
    final handle = username != null && username.isNotEmpty ? '@$username' : displayName;
    final text = '$handle kwenye Soko Vibe.\n$url';
    await _share(text);
    _track('profile_shared');
  }

  /// Secure order sharing — never exposes phone, address, payment, OTP, etc.
  /// The link is just the order reference; the destination authenticates.
  Future<void> shareOrder({required String orderId}) async {
    final url = DeepLinkParser.orderUrl(orderId);
    final text = 'Angalia oda yako kwenye Soko Vibe.\n$url';
    await _share(text);
    _track('order_shared');
  }

  Future<void> shareCategory({required String category}) async {
    final url = DeepLinkParser.categoryUrl(category);
    final text = 'Angalia $category kwenye Soko Vibe.\n$url';
    await _share(text);
    _track('category_shared');
  }

  Future<void> shareGeneric(String url, String text) async {
    await _share('$text\n$url');
  }

  Future<void> _share(String text) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      if (kDebugMode) debugPrint('ShareService share failed: $e');
    }
  }

  String _formatPrice(double price, String currency) {
    final symbol = currency == 'TZS' ? 'TSh' : currency;
    return '$symbol ${price.toStringAsFixed(0)}';
  }

  void _track(String event) {
    if (kDebugMode) debugPrint('Analytics: $event');
    // wiring to AnalyticsService can be added — ensure no PII logged
  }
}

/// Small helper to show a share preview bottom sheet if needed, but the
/// native share sheet is primary. This keeps UI consistent.
class SharePreview {
  static Widget productPreview({
    required String imageUrl,
    required String name,
    required String price,
    required String seller,
  }) {
    return Container();
  }
}
