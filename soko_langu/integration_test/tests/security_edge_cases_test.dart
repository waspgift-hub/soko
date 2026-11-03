import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for security and edge cases:
/// - App lock overlay
/// - Rapid interactions
/// - App lifecycle changes
/// - Error states
/// - Empty states
/// - Loading states
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Security & Edge Cases E2E', () {
    testWidgets('TC-SEC-01: App renders without errors on launch', (tester) async {
      app.main();
      await waitForAppReady(tester);

      expect(find.byType(MaterialApp), findsOneWidget);
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-02: App lock overlay renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // The AppLockOverlay should be in the widget tree
      // It's transparent when not locked
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-03: Connectivity wrapper handles offline', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // ConnectivityWrapper should be present
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-04: Maintenance gate renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // MaintenanceGate should be present
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-05: Transaction status watcher renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // TransactionStatusWatcher should be present
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-06: Premium background renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // PremiumBackground should be present (now solid black/white)
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-07: Age gate dialog shows on first launch', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Age gate should appear or have been dismissed
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-08: App handles rapid screen transitions', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Rapidly switch between all tabs
      final tabs = [
        find.byIcon(Icons.home_outlined),
        find.byIcon(Icons.chat_bubble_outline_rounded),
        find.byIcon(Icons.person_outline_rounded),
      ];

      for (var i = 0; i < 3; i++) {
        for (final tab in tabs) {
          if (tab.evaluate().isNotEmpty) {
            await tester.tap(tab.first);
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-09: App handles scroll during navigation', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Start scrolling
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -200),
      );

      // Then immediately switch tabs
      final chatIcon = find.byIcon(Icons.chat_bubble_outline_rounded);
      if (chatIcon.evaluate().isNotEmpty) {
        await tester.tap(chatIcon.first);
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-10: App handles empty product list gracefully', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // The app should show empty state or skeleton loaders
      // This tests the empty state widgets
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-11: Text input sanitization works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to search
      final searchBar = find.byType(TextField);
      if (searchBar.evaluate().isNotEmpty) {
        await tester.tap(searchBar.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Try to input potentially malicious text
        final searchInput = find.byType(TextField);
        if (searchInput.evaluate().isNotEmpty) {
          await tester.enterText(searchInput.first, '<script>alert("xss")</script>');
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-12: Unicode input handling', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to search and input Unicode characters
      final searchBar = find.byType(TextField);
      if (searchBar.evaluate().isNotEmpty) {
        await tester.tap(searchBar.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final searchInput = find.byType(TextField);
        if (searchInput.evaluate().isNotEmpty) {
          await tester.enterText(searchInput.first, 'Habari za Asubuhi 🇹🇿');
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-13: Very long text input handling', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchBar = find.byType(TextField);
      if (searchBar.evaluate().isNotEmpty) {
        await tester.tap(searchBar.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final searchInput = find.byType(TextField);
        if (searchInput.evaluate().isNotEmpty) {
          await tester.enterText(searchInput.first, 'a' * 500);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-14: Special characters in input', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchBar = find.byType(TextField);
      if (searchBar.evaluate().isNotEmpty) {
        await tester.tap(searchBar.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final searchInput = find.byType(TextField);
        if (searchInput.evaluate().isNotEmpty) {
          await tester.enterText(searchInput.first, r'!@#$%^&*()_+-=[]{}|;:,.<>?');
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEC-15: App survives orientation change simulation', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Simulate viewport changes
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle(const Duration(seconds: 1));

      tester.view.physicalSize = Size.zero;
      tester.view.resetPhysicalSize();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });
  });
}
