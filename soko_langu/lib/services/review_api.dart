import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/review_model.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Server-backed reviews client (`/api/v1/reviews`).
///
/// Phase D bridge: reviews read/write through Postgres (Prisma) behind
/// [ApiConfig.kUseReviewsApi] instead of the Firestore `reviews` collection.
/// The v1 API is HTTP, so list reads are one-shot fetches (callers that need a
/// stream wrap them) and writes upsert by (userId, productId). Review ids,
/// product ids and user ids are opaque strings that match the Firestore-era
/// contract, so the UI layer keeps working unchanged.
class ReviewApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  ReviewApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _token();
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  NetworkError _errorFor(int status, {String action = 'review request'}) =>
      NetworkError(
        message: 'Reviews failed ($status): $action',
        userMessage: ErrorKeys.poorNetwork,
      );

  Future<({List<Review> reviews, int total})> fetchProductReviews({
    required String productId,
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri.parse(
      ApiConfig.v1('/reviews/product/${Uri.encodeComponent(productId)}'),
    ).replace(queryParameters: {'page': '$page', 'limit': '$limit'});
    final res = await _http
        .get(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw _errorFor(res.statusCode);

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    final items = (data['reviews'] is List)
        ? (data['reviews'] as List)
              .whereType<Map<String, dynamic>>()
              .map(_parse)
              .toList()
        : <Review>[];
    final total = data['pagination'] is Map<String, dynamic>
        ? ((data['pagination'] as Map)['total'] as num?)?.toInt() ?? items.length
        : items.length;
    return (reviews: items, total: total);
  }

  /// Seller rating summary (average + star distribution + counts).
  Future<
      ({
        double averageRating,
        int totalReviews,
        int fiveStar,
        int fourStar,
        int threeStar,
        int twoStar,
        int oneStar,
      })> fetchSellerSummary({required String sellerId}) async {
    final uri = Uri.parse(
      ApiConfig.v1('/reviews/seller/${Uri.encodeComponent(sellerId)}/summary'),
    );
    final res = await _http
        .get(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw _errorFor(res.statusCode);

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    return (
      averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0,
      totalReviews: (data['totalReviews'] as num?)?.toInt() ?? 0,
      fiveStar: (data['fiveStar'] as num?)?.toInt() ?? 0,
      fourStar: (data['fourStar'] as num?)?.toInt() ?? 0,
      threeStar: (data['threeStar'] as num?)?.toInt() ?? 0,
      twoStar: (data['twoStar'] as num?)?.toInt() ?? 0,
      oneStar: (data['oneStar'] as num?)?.toInt() ?? 0,
    );
  }

  /// The current user's review for a product, or null when not reviewed yet.
  Future<Review?> fetchMyReview(String productId) async {
    final uri = Uri.parse(
      ApiConfig.v1('/reviews/product/${Uri.encodeComponent(productId)}/me'),
    );
    final res = await _http
        .get(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw _errorFor(res.statusCode);

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic> || data.isEmpty) return null;
    return _parse(data);
  }

  /// Creates or updates the caller's review for a product.
  Future<Review> upsertReview({
    required String productId,
    required double rating,
    String comment = '',
    String? sellerId,
  }) async {
    final uri = Uri.parse(ApiConfig.v1('/reviews'));
    final res = await _http
        .post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode({
            'productId': productId,
            'rating': rating,
            'comment': comment,
            if (sellerId != null && sellerId.trim().isNotEmpty) 'sellerId': sellerId.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw _errorFor(res.statusCode);

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) throw _errorFor(res.statusCode, action: 'upsert parse');
    return _parse(data);
  }

  /// Toggles the caller into/out of a review's helpful list.
  Future<bool> toggleHelpful(String reviewId) async {
    final uri = Uri.parse(ApiConfig.v1('/reviews/${Uri.encodeComponent(reviewId)}/helpful'));
    final res = await _http
        .post(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw _errorFor(res.statusCode);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is Map<String, dynamic> &&
        (body['data']?['liked'] as bool? ?? false);
  }

  /// Posts a seller reply (or clears it with an empty string).
  Future<Review> replyToReview(String reviewId, String reply) async {
    final uri = Uri.parse(ApiConfig.v1('/reviews/${Uri.encodeComponent(reviewId)}/reply'));
    final res = await _http
        .post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode({'reply': reply}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw _errorFor(res.statusCode);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) throw _errorFor(res.statusCode, action: 'reply parse');
    return _parse(data);
  }

  Review _parse(Map<String, dynamic> m) {
    return Review(
      id: m['id']?.toString() ?? '',
      productId: m['productId']?.toString() ?? '',
      sellerId: m['sellerId']?.toString() ?? '',
      userId: m['userId']?.toString() ?? '',
      userName: m['userName']?.toString() ?? 'Anonymous',
      userImage: m['userImage'] as String?,
      rating: (m['rating'] as num?)?.toDouble() ?? 0,
      comment: m['comment']?.toString() ?? '',
      createdAt: DateTime.tryParse(m['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      images: (m['images'] is List)
          ? List<String>.from((m['images'] as List).whereType<String>())
          : const [],
      helpfulCount: (m['helpfulCount'] as num?)?.toInt() ?? 0,
      isVerifiedPurchase: m['isVerifiedPurchase'] as bool? ?? false,
      likedBy: (m['likedBy'] is List)
          ? List<String>.from((m['likedBy'] as List).whereType<String>())
          : const [],
      sellerReply: m['sellerReply'] as String?,
      sellerReplyAt: m['sellerReplyAt'] != null
          ? DateTime.tryParse(m['sellerReplyAt'].toString())?.toLocal()
          : null,
    );
  }
}