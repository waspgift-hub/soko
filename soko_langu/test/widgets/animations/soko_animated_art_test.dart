import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soko_vibe/widgets/animations/soko_animated_art.dart';

void main() {
  Future<void> pumpArt(WidgetTester tester, Widget art) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: art)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('empty-state arts render and animate', (tester) async {
    await pumpArt(tester, const EmptyCartArt());
    expect(find.byType(CustomPaint), findsWidgets);
    await pumpArt(tester, const EmptyWishlistArt());
    await pumpArt(tester, const EmptyOrdersArt());
    await pumpArt(tester, const EmptyChatArt());
    await pumpArt(tester, const EmptySearchArt());
    expect(tester.takeException(), isNull);
  });

  testWidgets('success check plays once and settles', (tester) async {
    await pumpArt(tester, const SuccessCheckArt());
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
