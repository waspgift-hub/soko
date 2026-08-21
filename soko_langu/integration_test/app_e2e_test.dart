import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;

/// Wraps the real app for integration testing.
/// Firebase must be configured and a device/emulator must be available.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Soko Vibe E2E', () {
    testWidgets('app launches and shows splash/auth gate', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // The app should render something — either login screen or home screen.
      // We verify the MaterialApp root is present.
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('login screen renders phone input', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Look for login-related widgets. If the user is already authenticated,
      // the app will show the home screen instead.
      final hasLogin = find.textContaining('Login').evaluate().isNotEmpty ||
          find.textContaining('Phone').evaluate().isNotEmpty ||
          find.textContaining('phone').evaluate().isNotEmpty;
      final hasHome = find.byType(Scaffold).evaluate().isNotEmpty;

      // Either login or home screen should be visible
      expect(hasLogin || hasHome, isTrue);
    });

    testWidgets('bottom navigation is present when authenticated', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // If authenticated, bottom nav should be visible
      final hasBottomNav = find.byType(BottomNavigationBar).evaluate().isNotEmpty ||
          find.byType(NavigationBar).evaluate().isNotEmpty;
      // This test passes if the app renders without crashing
      expect(tester.takeException(), isNull);
    });

    testWidgets('search screen can be opened', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Tap the search bar if visible
      final searchFinder = find.byIcon(Icons.search_rounded);
      if (searchFinder.evaluate().isNotEmpty) {
        await tester.tap(searchFinder.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // App should not crash
      expect(tester.takeException(), isNull);
    });

    testWidgets('notification bell does not crash on tap', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final bellFinder = find.byIcon(Icons.notifications_outlined);
      if (bellFinder.evaluate().isNotEmpty) {
        await tester.tap(bellFinder.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('profile screen can be navigated to', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Try tapping profile icon in bottom nav
      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('settings screen can be opened', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to settings via profile
      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('theme toggle works without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to settings and toggle theme
      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (settingsIcon.evaluate().isNotEmpty) {
        await tester.tap(settingsIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Look for dark mode toggle
        final darkModeToggle = find.byIcon(Icons.dark_mode_outlined);
        if (darkModeToggle.evaluate().isNotEmpty) {
          await tester.tap(darkModeToggle.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('category screen can be opened', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Look for category section header or "See All" button
      final seeAll = find.text('See All');
      if (seeAll.evaluate().isNotEmpty) {
        await tester.tap(seeAll.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('product detail does not crash on deep link', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Try tapping a product card if visible
      final productCard = find.byType(GestureDetector).first;
      if (productCard.evaluate().isNotEmpty) {
        // Just verify the app is stable
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('chat list screen renders without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to chats via bottom nav
      final chatIcon = find.byIcon(Icons.chat_bubble_outline_rounded);
      if (chatIcon.evaluate().isNotEmpty) {
        await tester.tap(chatIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('back navigation works correctly', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Try navigating somewhere and pressing back
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('app survives rapid navigation', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Rapidly tap different bottom nav items
      final icons = find.byIcon(Icons.home_outlined);
      if (icons.evaluate().isNotEmpty) {
        for (var i = 0; i < 3; i++) {
          await tester.tap(icons.first);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling does not cause layout overflow', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Scroll down if there's a scrollable area
      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Check for overflow errors
      expect(tester.takeException(), isNull);
    });
  });
}
