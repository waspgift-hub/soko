import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// E2E test helpers for Soko Vibe integration tests.
///
/// These utilities are designed for use with `flutter test integration_test/`
/// on a real device or emulator with Firebase configured.

/// Waits for the app to fully initialize by looking for the home screen
/// or login screen.
Future<void> waitForAppReady(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(seconds: 8));
}

/// Taps a widget found by [SemanticsLabel] with retry logic.
/// Returns true if found and tapped, false otherwise.
Future<bool> tapBySemanticsLabel(
  WidgetTester tester,
  String label, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final finder = find.bySemanticsLabel(label);
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
      return true;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  return false;
}

/// Types text into the first [TextFormField] found.
Future<void> typeIntoFirstField(
  WidgetTester tester,
  String text,
) async {
  final finder = find.byType(TextFormField);
  if (finder.evaluate().isNotEmpty) {
    await tester.enterText(finder.first, text);
    await tester.pumpAndSettle();
  }
}

/// Scrolls until a widget with [text] is visible.
Future<void> scrollUntilVisible(
  WidgetTester tester,
  String text, {
  int maxScrolls = 20,
}) async {
  for (var i = 0; i < maxScrolls; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.drag(
      find.byType(Scaffold).first,
      const Offset(0, -300),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Verifies that no Flutter framework errors occurred.
void verifyNoErrors(WidgetTester tester) {
  final errors = tester.takeException();
  expect(errors, isNull, reason: 'Unexpected error: $errors');
}

/// Takes a screenshot (for CI/visual regression — no-op in headless test).
Future<void> takeScreenshot(
  WidgetTester tester,
  String name,
) async {
  // IntegrationTestWidgetsFlutterBinding.instance.takeScreenshot(name);
  // Screenshot capture is handled by the integration test runner.
}
