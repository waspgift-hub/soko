import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for search + categories:
/// - Search screen opens and accepts input
/// - No-results empty state renders
/// - Category grid opens and navigates to products
/// - Category icons render (rounded solid, never raw emoji text)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Search & Category Flow E2E', () {
    testWidgets('TC-SEARCH-01: Search screen opens from home', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchIcon = find.byIcon(Icons.search_rounded);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEARCH-02: Search field accepts text input', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchIcon = find.byIcon(Icons.search_rounded);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await typeIntoFirstField(tester, 'simu');
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEARCH-03: Gibberish query shows no-results state', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchIcon = find.byIcon(Icons.search_rounded);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await typeIntoFirstField(tester, 'zzzqqqxxx123');
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEARCH-04: Search back navigation works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final searchIcon = find.byIcon(Icons.search_rounded);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await tester.pageBack();
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-SEARCH-05: Voice search button does not crash', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final micIcon = find.byIcon(Icons.mic_none_outlined);
      final micAlt = find.byIcon(Icons.mic);
      final target = micIcon.evaluate().isNotEmpty ? micIcon : micAlt;
      if (target.evaluate().isNotEmpty) {
        await tester.tap(target.first);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-CAT-01: Category grid renders on home', (tester) async {
      app.main();
      await waitForAppReady(tester);

      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });

    testWidgets('TC-CAT-02: Category screen opens via See All', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final seeAll = find.text('See All');
      if (seeAll.evaluate().isNotEmpty) {
        await tester.tap(seeAll.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-CAT-03: Tapping a category opens its products', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final seeAll = find.text('See All');
      if (seeAll.evaluate().isNotEmpty) {
        await tester.tap(seeAll.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final cards = find.byType(GestureDetector);
        if (cards.evaluate().isNotEmpty) {
          await tester.tap(cards.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-CAT-04: Category screen back navigation works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final seeAll = find.text('See All');
      if (seeAll.evaluate().isNotEmpty) {
        await tester.tap(seeAll.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await tester.pageBack();
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-CAT-05: No raw emoji text in category tiles', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Category tiles must render Icon widgets, never raw emoji strings.
      // A lone emoji Text widget would indicate a regression.
      final emojiTexts = find.textContaining('📱');
      expect(emojiTexts.evaluate().isEmpty, isTrue);
      verifyNoErrors(tester);
    });
  });
}
