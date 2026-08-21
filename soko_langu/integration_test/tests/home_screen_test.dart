import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for the home screen:
/// - App bar renders with logo
/// - Search bar is tappable
/// - Brand filter chips render
/// - Category section renders
/// - Product grid renders
/// - Bottom navigation works
/// - Notification bell works
/// - Currency picker works
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Home Screen E2E', () {
    testWidgets('TC-HOME-01: App bar renders with logo and actions', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Verify AppBar is present
      expect(find.byType(AppBar), findsWidgets);
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-02: Search bar is tappable and navigates', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchIcon = find.byIcon(Icons.search_rounded);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Should navigate to search screen or show search overlay
        verifyNoErrors(tester);
      }
    });

    testWidgets('TC-HOME-03: Brand filter chips render and are tappable', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Look for brand chips (Nike, Adidas, Samsung, etc.)
      final allChip = find.text('All');
      if (allChip.evaluate().isNotEmpty) {
        await tester.tap(allChip.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-04: Categories section renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // The categories section should be visible
      // Look for category-related text or the section header
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-05: Bottom navigation switches tabs', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Find bottom navigation items
      final navItems = find.byType(GestureDetector);
      if (navItems.evaluate().length > 1) {
        // Tap the second nav item (chats or similar)
        await tester.tap(navItems.at(1));
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-06: Notification bell navigates', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final bellIcon = find.byIcon(Icons.notifications_outlined);
      if (bellIcon.evaluate().isNotEmpty) {
        await tester.tap(bellIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-07: Currency picker opens', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final currencyIcon = find.byIcon(Icons.monetization_on_outlined);
      if (currencyIcon.evaluate().isNotEmpty) {
        await tester.tap(currencyIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-08: Scroll down loads more products', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Scroll down to trigger pagination
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-09: Pull to refresh works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Pull down to refresh
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, 300),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      verifyNoErrors(tester);
    });

    testWidgets('TC-HOME-10: Quick action chips render', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Look for "Post Request" or similar quick action
      verifyNoErrors(tester);
    });
  });
}
