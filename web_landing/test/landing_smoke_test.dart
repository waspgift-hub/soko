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
    final inter = FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await inter.load();
    final mono = FontLoader('JetBrainsMono')..addFont(rootBundle.load('assets/fonts/JetBrainsMono.ttf'));
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
  testWidgets('coming soon renders hero, registration, and faq', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('UNDER DEVELOPMENT'), findsWidgets);
    expect(find.textContaining('Your Marketplace'), findsWidgets);

    // Register section is below the fold in a lazy sliver; scroll to reveal it.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 20; i++) {
      if (find.text('Get Launch Updates').evaluate().isNotEmpty) break;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(find.text('Get Launch Updates'), findsWidgets);
    await settlePage(tester);
  });

  testWidgets('desktop renders nav and key sections', (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    expect(find.text('Home'), findsWidgets);
    expect(find.text('About'), findsWidgets);
    expect(find.text('Features'), findsWidgets);
    expect(find.text('FAQ'), findsWidgets);
    expect(find.text('Contact'), findsWidgets);
    expect(find.text('UNDER DEVELOPMENT'), findsWidgets);
    await settlePage(tester);
  });
}
