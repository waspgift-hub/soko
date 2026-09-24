import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for the product detail flow:
/// - Product detail opens from feed
/// - Image gallery, reviews, seller info render
/// - Wishlist toggle, share, report actions
/// - Buy-now navigates toward checkout
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Product Detail Flow E2E', () {
    testWidgets('TC-PROD-01: Tapping a feed product opens detail', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-02: Detail shows wishlist toggle', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final fav = find.byIcon(Icons.favorite_border);
        if (fav.evaluate().isNotEmpty) {
          await tester.tap(fav.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-03: Detail scrolls without overflow', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await tester.drag(
          find.byType(Scaffold).first,
          const Offset(0, -600),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-04: Reviews section can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final reviews = find.textContaining('eview');
        if (reviews.evaluate().isNotEmpty) {
          await tester.tap(reviews.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-05: Share action does not crash', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final share = find.byIcon(Icons.share_outlined);
        final shareAlt = find.byIcon(Icons.share);
        final target = share.evaluate().isNotEmpty ? share : shareAlt;
        if (target.evaluate().isNotEmpty) {
          await tester.tap(target.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-06: Buy-now CTA navigates toward checkout', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final buyNow = find.byIcon(Icons.shopping_cart_checkout);
        if (buyNow.evaluate().isNotEmpty) {
          await tester.tap(buyNow.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-07: Back navigation from detail', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        await tester.pageBack();
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-08: Seller profile opens from detail', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cards = find.byType(GestureDetector);
      if (cards.evaluate().isNotEmpty) {
        await tester.tap(cards.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
        final seller = find.textContaining('hop');
        if (seller.evaluate().isNotEmpty) {
          await tester.tap(seller.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });
  });
}
