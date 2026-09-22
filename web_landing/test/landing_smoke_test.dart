import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_web/main.dart';
import 'package:visibility_detector/visibility_detector.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // Synchronous visibility callbacks in tests: the default 500ms debounce
  // Timer would otherwise stay pending at teardown and fail the test.
  // Production keeps the default interval (untouched).
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  // Load bundled fonts deterministically: otherwise the first frames lay
  // out with fallback metrics and overflow assertions flake run to run.
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await inter.load();
    final mono = FontLoader('JetBrainsMono')
      ..addFont(rootBundle.load('assets/fonts/JetBrainsMono.ttf'));
    await mono.load();
  });
  await tester.pumpWidget(const SokoVibeWebApp());
  await tester.pump();
}

/// Scrolls until the text is built, then asserts exactly one match.
/// (CustomScrollView builds slivers lazily, so offscreen sections need this.)
Future<void> expectVisible(WidgetTester tester, String text) async {
  // Nudge the page down until the lazily-built sliver appears. Manual
  // jumpTo + fixed pumps (never pumpAndSettle): visibility_detector keeps a
  // 500ms debounce timer alive on every paint, which would hang settlement.
  for (var i = 0; i < 60; i++) {
    if (find.text(text).evaluate().isNotEmpty) break;
    final s =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final next =
        (s.position.pixels + 500).clamp(0.0, s.position.maxScrollExtent);
    if (next == s.position.pixels) break;
    s.position.jumpTo(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
  expect(find.text(text), findsOneWidget);
}

/// Drains page timers (typing demo, reveal animations, visibility debounce)
/// so teardown never sees a pending Timer. Fake time: instant in tests.
Future<void> settlePage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}

void main() {
  testWidgets('mobile renders hero, features, escrow, faq',
      (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.text('Nunua kwa uhakika.'), findsOneWidget);
    expect(find.text('Uza kwa ujasiri.'), findsOneWidget);
    expect(find.text('Anza Kununua'), findsWidgets);
    await expectVisible(tester, 'Ununuzi unaanza kwa kuamini.');
    await expectVisible(tester, 'Fedha zako hazitoki mpaka upokee.');
    await settlePage(tester);
  });

  testWidgets('desktop renders nav links and wide grid', (tester) async {
    await pumpAt(tester, const Size(1440, 900));

    expect(find.text('Jinsi Inavyofanya Kazi'), findsWidgets);
    expect(find.text('Kwa Wauzaji'), findsWidgets);
    await expectVisible(
        tester, 'Karibu kwenye soko linalofuata la Tanzania.');
    await settlePage(tester);
  });
}
