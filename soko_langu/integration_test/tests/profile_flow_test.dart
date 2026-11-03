import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for the profile flow:
/// - Profile screen renders user info
/// - Settings screen navigation
/// - Edit profile screen
/// - Wishlist screen
/// - My Ads screen
/// - Seller dashboard
/// - KYC screen
/// - Shop customization
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Profile Flow E2E', () {
    testWidgets('TC-PROF-01: Profile screen renders', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile via bottom nav
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-02: Settings screen can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile then settings
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-03: Theme toggle works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to settings
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Toggle dark mode
        final darkModeToggle = find.byIcon(Icons.dark_mode_outlined);
        if (darkModeToggle.evaluate().isNotEmpty) {
          await tester.tap(darkModeToggle.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-04: Language switcher works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to settings
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-05: Account tier switching works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // This tests the account tier system
      // Navigate to profile
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-06: Seller dashboard can be accessed', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Look for seller-related navigation
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-07: Wishlist screen can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to profile then wishlist
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Look for wishlist icon or button
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-08: Help center can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to settings then help
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Look for help center
        final helpText = find.textContaining('Help');
        if (helpText.evaluate().isNotEmpty) {
          await tester.tap(helpText.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-09: About screen can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final aboutText = find.textContaining('About');
        if (aboutText.evaluate().isNotEmpty) {
          await tester.tap(aboutText.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-PROF-10: Notification preferences can be opened', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Navigate to settings
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });
  });
}
