import 'package:flutter/foundation.dart';

/// All shareable / deep-linkable entity types in Soko Vibe.
enum DeepLinkType {
  product,
  seller,
  profile,
  order,
  otp,
  category,
  search,
  unknown,
}

/// Immutable parsed representation of a Soko Vibe web URL.
///
/// The parser is the single source of truth — no screen scatters URL slicing.
class DeepLinkRoute {
  final DeepLinkType type;
  final String id;
  final Map<String, String> query;
  final Uri rawUri;
  final String internalLocation;

  const DeepLinkRoute({
    required this.type,
    required this.id,
    required this.query,
    required this.rawUri,
    required this.internalLocation,
  });

  /// True for routes that require authentication before showing private data.
  bool get isPrivate =>
      type == DeepLinkType.order || type == DeepLinkType.otp;

  /// True for routes that can be shown without login.
  bool get isPublic => !isPrivate;

  @override
  String toString() =>
      'DeepLinkRoute(type=$type id=$id location=$internalLocation)';
}

class DeepLinkParser {
  DeepLinkParser._();

  static const List<String> allowedHosts = [
    'www.sokovibe.co.tz',
    'sokovibe.co.tz',
    'api.sokovibe.co.tz',
    'www.soko-vibe.co.tz',
    'soko-vibe.co.tz',
  ];

  static const String webBaseUrl = 'https://www.sokovibe.co.tz';

  /// Parses an incoming URI into a [DeepLinkRoute] or null when not a
  /// Soko Vibe deep link. Never throws.
  static DeepLinkRoute? parse(Uri uri) {
    try {
      if (uri.scheme != 'https' && uri.scheme != 'http') return null;
      final host = uri.host.toLowerCase();
      if (!allowedHosts.contains(host)) return null;

      final segs =
          uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final query = Map<String, String>.from(uri.queryParameters);

      if (segs.isEmpty) {
        // root or search with q
        if (query.containsKey('q') || query.containsKey('search')) {
          final q = query['q'] ?? query['search'] ?? '';
          if (q.isNotEmpty) {
            return DeepLinkRoute(
              type: DeepLinkType.search,
              id: q,
              query: query,
              rawUri: uri,
              internalLocation: '/search?q=${Uri.encodeComponent(q)}',
            );
          }
        }
        return null;
      }

      // /search?q=phones
      if (segs[0].toLowerCase() == 'search') {
        final q = query['q'] ?? query['search'] ?? '';
        if (q.isEmpty && segs.length > 1) {
          final q2 = segs.sublist(1).join(' ');
          return DeepLinkRoute(
            type: DeepLinkType.search,
            id: q2,
            query: query,
            rawUri: uri,
            internalLocation: '/search?q=${Uri.encodeComponent(q2)}',
          );
        }
        return DeepLinkRoute(
          type: DeepLinkType.search,
          id: q,
          query: query,
          rawUri: uri,
          internalLocation:
              q.isEmpty ? '/search' : '/search?q=${Uri.encodeComponent(q)}',
        );
      }

      // Need at least 2 segments for most types except search
      if (segs.length < 2) {
        // /category or /c ?
        if (segs[0].toLowerCase() == 'category' ||
            segs[0].toLowerCase() == 'c') {
          return null; // need id
        }
        return null;
      }

      final first = segs[0].toLowerCase();
      final id = segs[1].trim();
      if (id.isEmpty || id.length > 128) return null;
      if (!_isSafeId(id)) return null;

      switch (first) {
        case 'product':
        case 'p':
          return DeepLinkRoute(
            type: DeepLinkType.product,
            id: id,
            query: query,
            rawUri: uri,
            internalLocation: '/product/$id',
          );
        case 'seller':
        case 'store':
        case 'shop':
          return DeepLinkRoute(
            type: DeepLinkType.seller,
            id: id,
            query: query,
            rawUri: uri,
            internalLocation: '/public-profile/$id',
          );
        case 'profile':
        case 'user':
        case 'u':
          return DeepLinkRoute(
            type: DeepLinkType.profile,
            id: id,
            query: query,
            rawUri: uri,
            internalLocation: '/public-profile/$id',
          );
        case 'order':
        case 'orders':
        case 'receipt':
          return DeepLinkRoute(
            type: DeepLinkType.order,
            id: id,
            query: query,
            rawUri: uri,
            internalLocation: '/order-detail/$id',
          );
        case 'otp':
        case 'handover':
        case 'action':
          // Never expose OTP code — id is orderId, not OTP secret
          return DeepLinkRoute(
            type: DeepLinkType.otp,
            id: id,
            query: query,
            rawUri: uri,
            internalLocation: '/order-detail/$id',
          );
        case 'category':
        case 'categories':
        case 'c':
          final catName = Uri.decodeComponent(id);
          return DeepLinkRoute(
            type: DeepLinkType.category,
            id: catName,
            query: query,
            rawUri: uri,
            internalLocation:
                '/category-products/${Uri.encodeComponent(catName)}',
          );
        default:
          return null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DeepLinkParser parse error: $e for $uri');
      return null;
    }
  }

  static bool _isSafeId(String id) {
    // Disallow control chars, spaces, dangerous patterns; allow alnum, - _ .
    if (id.contains('..') || id.contains('//')) return false;
    if (id.contains(' ') || id.contains('\n') || id.contains('\r')) return false;
    // username may contain @ at start, strip for check
    final check = id.startsWith('@') ? id.substring(1) : id;
    if (check.isEmpty) return false;
    // allow longer check but still safe: if not matching strict, still allow
    // Firebase UIDs contain alphanumeric, but products ids are uuid like.
    // Fail only if contains suspicious chars < > " ' `
    if (id.contains('<') ||
        id.contains('>') ||
        id.contains('"') ||
        id.contains("'") ||
        id.contains('`') ||
        id.contains('\\')) return false;
    return true;
  }

  // Helpers to generate share URLs
  static String productUrl(String productId) => '$webBaseUrl/product/$productId';
  static String sellerUrl(String sellerId) => '$webBaseUrl/seller/$sellerId';
  static String profileUrl(String userIdOrUsername) =>
      '$webBaseUrl/profile/$userIdOrUsername';
  static String orderUrl(String orderId) => '$webBaseUrl/order/$orderId';
  static String categoryUrl(String category) =>
      '$webBaseUrl/category/${Uri.encodeComponent(category)}';
  static String searchUrl(String query) =>
      '$webBaseUrl/search?q=${Uri.encodeComponent(query)}';
  // Never generate OTP url with code — only order context
  static String otpUrl(String orderId) => '$webBaseUrl/otp/$orderId';
}
