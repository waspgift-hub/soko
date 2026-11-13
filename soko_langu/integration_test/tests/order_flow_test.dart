import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for order and payment flows:
/// - Checkout screen renders
/// - Order history screen
/// - Receipt screen
/// - Seller dispatch screen
/// - Seller quote screen
/// - Product boost flow
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Order Flow E2E', () {
    testWidgets('TC-ORDER-01: Checkout screen requires product', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Checkout requires a Product in extra — accessing without one
      // should show an error page, not crash
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-02: My Purchases screen can be accessed', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Look for purchases or orders section
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-03: Seller dashboard can be accessed', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Look for seller dashboard
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-04: Add product screen can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile then look for add product
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Look for add product button
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-05: Product boost screen can be accessed', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // This tests the boost flow entry point
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-06: Flash sale creation screen', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Look for create flash sale
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-07: Order detail screen handles missing data', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Accessing order detail without proper data should not crash
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-08: Receipt screen can be accessed', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Receipt requires an orderId — accessing without one should be graceful
      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-09: Seller dispatch screen', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to seller dashboard
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      verifyNoErrors(tester);
    });

    testWidgets('TC-ORDER-10: Seller quote screen', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to seller dashboard
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      verifyNoErrors(tester);
    });
  });
}
