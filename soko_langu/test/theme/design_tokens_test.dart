import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/theme/design_tokens.dart';

void main() {
  group('Design Tokens — Ds', () {
    test('spacing constants match app_dimens', () {
      expect(Ds.sp1, 4);
      expect(Ds.sp2, 8);
      expect(Ds.sp3, 12);
      expect(Ds.sp4, 16);
      expect(Ds.sp5, 20);
      expect(Ds.sp6, 24);
      expect(Ds.sp7, 32);
      expect(Ds.sp8, 40);
      expect(Ds.sp9, 48);
      expect(Ds.sp10, 64);
    });

    test('radius constants are sensible', () {
      expect(Ds.rSm, greaterThanOrEqualTo(4));
      expect(Ds.rMd, greaterThanOrEqualTo(Ds.rSm));
      expect(Ds.rLg, greaterThanOrEqualTo(Ds.rMd));
      expect(Ds.rXl, greaterThanOrEqualTo(Ds.rLg));
      expect(Ds.rFull, 999);
    });

    test('haptic methods do not throw', () {
      expect(() => Ds.tap(), returnsNormally);
      expect(() => Ds.light(), returnsNormally);
      expect(() => Ds.medium(), returnsNormally);
      expect(() => Ds.heavy(), returnsNormally);
    });

    test('content constraints are correct', () {
      expect(Ds.maxFormWidth, 440);
      expect(Ds.maxContentWidth, 600);
    });

    test('typography methods return TextStyle', () {
      final c = Colors.blue;
      expect(Ds.displayLg(c), isA<TextStyle>());
      expect(Ds.headingMd(c), isA<TextStyle>());
      expect(Ds.bodyLg(c), isA<TextStyle>());
      expect(Ds.bodyMd(c), isA<TextStyle>());
      expect(Ds.labelMd(c), isA<TextStyle>());
      expect(Ds.amount(c), isA<TextStyle>());
    });

    test('brandGradient returns LinearGradient', () {
      final g = Ds.brandGradient(Colors.green);
      expect(g, isA<LinearGradient>());
      expect(g.colors.length, 2);
    });

    testWidgets('DsContext extension provides cs getter', (tester) async {
      late ColorScheme capturedCs;
      late bool capturedDark;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) {
            capturedCs = ctx.cs;
            capturedDark = ctx.isDark;
            return const Scaffold();
          },
        ),
      ));

      expect(capturedCs, isA<ColorScheme>());
      expect(capturedDark, isFalse);
    });
  });
}
