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
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
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

Future<void> settlePage(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('landing renders hero, registration, and waitlist CTA', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.textContaining('Soko Vibe'), findsWidgets);

    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 24; i++) {
      if (find.textContaining('Notify').evaluate().isNotEmpty ||
          find.textContaining('Nijulishe').evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          ((w.data ?? '').contains('Notify Me') ||
              (w.data ?? '').contains('Nijulishe') ||
              (w.data ?? '').contains('Get Launch Updates') ||
              (w.data ?? '').contains('Pata Taarifa'))),
      findsWidgets,
    );
    await settlePage(tester);
  });

  testWidgets('desktop renders nav and key sections', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.byTooltip('Menu'), findsNothing);
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          ((w.data ?? '') == 'Home' || (w.data ?? '') == 'Mwanzo')),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && ((w.data ?? '') == 'FAQ' || (w.data ?? '') == 'Maswali')),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          ((w.data ?? '') == 'Contact' || (w.data ?? '') == 'Mawasiliano')),
      findsWidgets,
    );
    await settlePage(tester);
  });
}
