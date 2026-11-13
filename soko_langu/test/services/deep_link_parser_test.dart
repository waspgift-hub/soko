import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/deep_link_parser.dart';

void main() {
  group('DeepLinkParser product URLs', () {
    test('parses canonical /product/{id}', () {
      final route = DeepLinkParser.parse(
        Uri.parse('https://www.sokovibe.co.tz/product/abc-123'),
      );
      expect(route, isNotNull);
      expect(route!.type, DeepLinkType.product);
      expect(route.id, 'abc-123');
      expect(route.internalLocation, '/product/abc-123');
    });

    test('parses short /p/{id} alias', () {
      final route = DeepLinkParser.parse(
        Uri.parse('https://sokovibe.co.tz/p/abc-123'),
      );
      expect(route, isNotNull);
      expect(route!.type, DeepLinkType.product);
      expect(route.id, 'abc-123');
      expect(route.internalLocation, '/product/abc-123');
    });

    test('preserves safe referral query without using it as auth', () {
      final route = DeepLinkParser.parse(
        Uri.parse('https://www.sokovibe.co.tz/p/abc-123?ref=user_9'),
      );
      expect(route!.query['ref'], 'user_9');
      expect(route.isPublic, isTrue);
      expect(route.internalLocation, contains('ref=user_9'));
    });

    test('rejects malformed product ids', () {
      expect(
        DeepLinkParser.parse(
          Uri.parse('https://www.sokovibe.co.tz/p/../secret'),
        ),
        isNull,
      );
      expect(
        DeepLinkParser.parse(
          Uri.parse('https://www.sokovibe.co.tz/p/<script>'),
        ),
        isNull,
      );
    });

    test('ignores foreign hosts', () {
      expect(
        DeepLinkParser.parse(Uri.parse('https://evil.example/p/abc-123')),
        isNull,
      );
    });

    test('builds canonical share URL', () {
      expect(
        DeepLinkParser.productUrl('abc-123'),
        'https://www.sokovibe.co.tz/product/abc-123',
      );
    });
  });
}
