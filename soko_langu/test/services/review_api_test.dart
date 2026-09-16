import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/review_api.dart';

void main() {
  group('ReviewApiClient', () {
    test('fetchProductReviews maps envelope to reviews + total', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/reviews/product/p1');
        expect(request.url.queryParameters['page'], '1');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'reviews': [
                {
                  'id': 'r1',
                  'productId': 'p1',
                  'sellerId': 's1',
                  'userId': 'u1',
                  'userName': 'Asha',
                  'rating': 4,
                  'comment': 'Very good',
                  'createdAt': '2026-09-01T10:00:00.000Z',
                  'helpfulCount': 2,
                  'likedBy': ['u2'],
                  'isVerifiedPurchase': true,
                  'images': [],
                },
              ],
              'pagination': {'page': 1, 'limit': 20, 'total': 1},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => 'tok');
      final result = await api.fetchProductReviews(productId: 'p1');

      expect(result.reviews, hasLength(1));
      expect(result.total, 1);
      final r = result.reviews.first;
      expect(r.id, 'r1');
      expect(r.userName, 'Asha');
      expect(r.rating, 4.0);
      expect(r.helpfulCount, 2);
      expect(r.likedBy, ['u2']);
      expect(r.isVerifiedPurchase, true);
      expect(r.createdAt.year, 2026);
    });

    test('fetchSellerSummary maps distribution', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'averageRating': 4.2,
              'totalReviews': 10,
              'fiveStar': 6,
              'fourStar': 3,
              'threeStar': 1,
              'twoStar': 0,
              'oneStar': 0,
            },
          }),
          200,
        );
      });

      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => null);
      final s = await api.fetchSellerSummary(sellerId: 's1');

      expect(s.averageRating, 4.2);
      expect(s.totalReviews, 10);
      expect(s.fiveStar, 6);
      expect(s.oneStar, 0);
    });

    test('fetchMyReview returns null on 404', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'success': false}), 404),
      );
      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => null);
      expect(await api.fetchMyReview('p1'), isNull);
    });

    test('fetchMyReview parses existing review', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'r9',
              'productId': 'p1',
              'sellerId': 's1',
              'userId': 'u1',
              'userName': 'Juma',
              'rating': 5,
              'comment': 'Nice',
              'createdAt': '2026-09-02T08:00:00.000Z',
              'helpfulCount': 0,
              'likedBy': [],
              'isVerifiedPurchase': false,
              'images': [],
            },
          }),
          200,
        ),
      );
      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => null);
      final r = await api.fetchMyReview('p1');
      expect(r, isNotNull);
      expect(r!.userName, 'Juma');
      expect(r.rating, 5.0);
    });

    test('upsertReview posts body and parses response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/reviews');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['productId'], 'p1');
        expect(body['rating'], 4);
        expect(body['comment'], 'Ok');
        expect(request.headers['Authorization'], 'Bearer tok');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'r2',
              'productId': 'p1',
              'sellerId': 's1',
              'userId': 'u1',
              'userName': 'Asha',
              'rating': 4,
              'comment': 'Ok',
              'createdAt': '2026-09-03T10:00:00.000Z',
              'helpfulCount': 0,
              'likedBy': [],
              'isVerifiedPurchase': false,
              'images': [],
            },
          }),
          200,
        );
      });

      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => 'tok');
      final r = await api.upsertReview(productId: 'p1', rating: 4, comment: 'Ok');
      expect(r.id, 'r2');
    });

    test('toggleHelpful flips the liked flag', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'success': true, 'data': {'liked': true, 'helpfulCount': 3, 'likedBy': ['u1']}}),
          200,
        ),
      );
      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => null);
      expect(await api.toggleHelpful('r1'), isTrue);
    });

    test('replyToReview posts the reply', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/reviews/r1/reply');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reply'], 'Thank you!');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'r1',
              'productId': 'p1',
              'sellerId': 's1',
              'userId': 'u1',
              'userName': 'Asha',
              'rating': 4,
              'comment': 'Ok',
              'createdAt': '2026-09-03T10:00:00.000Z',
              'helpfulCount': 0,
              'likedBy': [],
              'isVerifiedPurchase': false,
              'images': [],
              'sellerReply': 'Thank you!',
              'sellerReplyAt': '2026-09-04T10:00:00.000Z',
            },
          }),
          200,
        );
      });
      final api = ReviewApiClient(httpClient: client, tokenProvider: () async => null);
      final r = await api.replyToReview('r1', 'Thank you!');
      expect(r.sellerReply, 'Thank you!');
      expect(r.sellerReplyAt, isNotNull);
    });
  });
}
