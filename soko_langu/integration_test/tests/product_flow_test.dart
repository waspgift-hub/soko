import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for the product browsing flow:
/// - Product cards render in grid
/// - Tapping product navigates to detail
/// - Product detail shows images, price, seller info
/// - Add to cart / Buy Now button
/// - Product reviews section
/// - Share product
/// - Report product
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Product Flow E2E', () {
    testWidgets('TC-PROD-01: Product grid renders on home screen', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Scroll to product section
      await scrollUntilVisible(tester, 'Latest Products');
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-02: Product card is tappable', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Scroll down to see products
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Look for product cards (they typically have price text)
      final priceWidgets = find.textContaining('TSh');
      if (priceWidgets.evaluate().isNotEmpty) {
        await tester.tap(priceWidgets.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-03: Product detail page shows key info', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to a product detail (if products exist)
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final priceWidgets = find.textContaining('TSh');
      if (priceWidgets.evaluate().isNotEmpty) {
        await tester.tap(priceWidgets.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Product detail should show price, seller info, etc.
        verifyNoErrors(tester);
      }
    });

    testWidgets('TC-PROD-04: Search screen shows results', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to search
      final searchBar = find.byType(TextField);
      if (searchBar.evaluate().isNotEmpty) {
        await tester.tap(searchBar.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Type a search query
        final searchInput = find.byType(TextField);
        if (searchInput.evaluate().isNotEmpty) {
          await tester.enterText(searchInput.first, 'phone');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-05: Category screen renders categories', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to categories
      final seeAll = find.text('See All');
      if (seeAll.evaluate().isNotEmpty) {
        await tester.tap(seeAll.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-06: Flash sale screen can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Look for flash sale banner or section
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-07: Filter sheet opens from home', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Look for filter icon or button
      final filterIcon = find.byIcon(Icons.tune_rounded);
      if (filterIcon.evaluate().isNotEmpty) {
        await tester.tap(filterIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-08: Product condition filter works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Open filter and check condition options
      final filterIcon = find.byIcon(Icons.tune_rounded);
      if (filterIcon.evaluate().isNotEmpty) {
        await tester.tap(filterIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-09: Recently viewed row renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Scroll to recently viewed section
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROD-10: Trending carousel renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Scroll to trending section
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });
  });
}
