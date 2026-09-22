import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/widgets/ds/animated_press.dart';

Widget harness({VoidCallback? onTap, double pressedScale = 0.97}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: AnimatedPress(
          onTap: onTap,
          pressedScale: pressedScale,
          child: const SizedBox(width: 100, height: 50),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tap fires onTap and the spring settles back to rest',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(harness(onTap: () => tapped = true));

    await tester.tap(find.byType(AnimatedPress));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    final scale =
        tester.widget<ScaleTransition>(find.descendant(of: find.byType(AnimatedPress), matching: find.byType(ScaleTransition))).scale;
    // Springs stop at simulation tolerance, not exactly 1.0.
    expect(scale.value, moreOrLessEquals(1.0, epsilon: 1e-3));
  });

  testWidgets('press dips below rest scale mid-spring', (tester) async {
    await tester.pumpWidget(harness(onTap: () {}));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(AnimatedPress)));
    // Flush the pointer event so _down starts the spring, then advance it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final scale =
        tester.widget<ScaleTransition>(find.descendant(of: find.byType(AnimatedPress), matching: find.byType(ScaleTransition))).scale;
    expect(scale.value, lessThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
    final rested =
        tester.widget<ScaleTransition>(find.descendant(of: find.byType(AnimatedPress), matching: find.byType(ScaleTransition))).scale;
    expect(rested.value, moreOrLessEquals(1.0, epsilon: 1e-3));
  });

  testWidgets('reduced motion degrades to a plain tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: harness(onTap: () => tapped = true),
      ),
    );

    await tester.tap(find.byType(AnimatedPress));
    await tester.pump();

    expect(tapped, isTrue);
    final scale =
        tester.widget<ScaleTransition>(find.descendant(of: find.byType(AnimatedPress), matching: find.byType(ScaleTransition))).scale;
    expect(scale.value, equals(1.0));
  });
}
