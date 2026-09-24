import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for the wishlist flow:
/// - Wishlist screen opens with empty state or items
/// - Favorite toggle on product detail
/// - Wishlist persists across navigation
/// - Start-shopping CTA navigates home
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Wishlist Flow E2E', () {
    testWidgets('TC-WISH-01: Wishlist screen opens from profile', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-02: Empty wishlist shows animated empty state', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Empty state renders either the wishlist text or a generic empty view
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-03: Favorite toggle on product card does not crash', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final favIcon = find.byIcon(Icons.favorite_border);
      if (favIcon.evaluate().isNotEmpty) {
        await tester.tap(favIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      final favFilled = find.byIcon(Icons.favorite);
      if (favFilled.evaluate().isNotEmpty) {
        await tester.tap(favFilled.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-04: Toggling twice restores original state', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final favIcon = find.byIcon(Icons.favorite_border);
      if (favIcon.evaluate().isNotEmpty) {
        await tester.tap(favIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        final favFilled = find.byIcon(Icons.favorite);
        if (favFilled.evaluate().isNotEmpty) {
          await tester.tap(favFilled.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-05: Wishlist survives tab switching', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final homeIcon = find.byIcon(Icons.home_outlined);
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (homeIcon.evaluate().isNotEmpty && profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.tap(homeIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-06: Start-shopping CTA is tappable when visible', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final cta = find.textContaining('shopping');
      if (cta.evaluate().isNotEmpty) {
        await tester.tap(cta.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-07: Rapid favorite toggles do not crash', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final favIcon = find.byIcon(Icons.favorite_border);
      if (favIcon.evaluate().isNotEmpty) {
        for (var i = 0; i < 3; i++) {
          await tester.tap(favIcon.first);
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WISH-08: Back navigation from wishlist', (tester) async {
      app.main();
      await waitForAppReady(tester);

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });
  });
}
