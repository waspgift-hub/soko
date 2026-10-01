import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/theme/app_colors.dart';
import 'package:soko_vibe/theme/app_themes.dart';
import 'package:soko_vibe/widgets/ds/input_validators.dart';
import 'package:soko_vibe/widgets/ds/standard_input_field.dart';

Widget harness(
  Widget child, {
  GlobalKey<FormState>? formKey,
  Brightness brightness = Brightness.light,
  AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? buildDarkTheme(const Color(0xFF00C853))
        : buildLightTheme(const Color(0xFF00C853)),
    home: Scaffold(
      body: Form(
        key: formKey,
        autovalidateMode: autovalidateMode,
        child: Center(child: SizedBox(width: 340, child: child)),
      ),
    ),
  );
}

/// Reads the border colour the field is currently drawing, so tests assert on
/// the rendered chrome rather than on internal state.
Color edgeColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(StandardInputField),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (container.decoration as BoxDecoration).border!.top.color;
}

void main() {
  group('StandardInputField — chrome', () {
    testWidgets('idle uses the hairline edge', (tester) async {
      await tester.pumpWidget(harness(const StandardInputField(label: 'Name')));

      final scheme = Theme.of(
        tester.element(find.byType(StandardInputField)),
      ).colorScheme;
      expect(edgeColor(tester), scheme.hairline);
    });

    testWidgets('focus switches the edge to the primary colour', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const StandardInputField(label: 'Name')));
      final scheme = Theme.of(
        tester.element(find.byType(StandardInputField)),
      ).colorScheme;

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(edgeColor(tester), scheme.primary);
    });

    testWidgets('errorText paints the error edge and the message', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(const StandardInputField(label: 'Name', errorText: 'Required')),
      );
      final scheme = Theme.of(
        tester.element(find.byType(StandardInputField)),
      ).colorScheme;

      expect(edgeColor(tester), scheme.error);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('disabled dims the field and blocks input', (tester) async {
      var changed = false;
      await tester.pumpWidget(
        harness(
          StandardInputField(
            label: 'Email',
            enabled: false,
            onChanged: (_) => changed = true,
          ),
        ),
      );

      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(StandardInputField),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pump();
      expect(changed, isFalse);
    });

    testWidgets('valid value shows the success badge once unfocused', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        harness(
          StandardInputField(
            controller: controller,
            label: 'Email',
            keyboard: DsKeyboard.email,
            showSuccess: true,
          ),
        ),
      );
      final scheme = Theme.of(
        tester.element(find.byType(StandardInputField)),
      ).colorScheme;

      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.enterText(find.byType(TextField), 'juma@sokovibe.co.tz');
      await tester.pumpAndSettle();
      // Still focused while typing, so the badge waits for blur.
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // The success edge is deliberately softened so the check badge, not the
      // outline, is what confirms the value.
      expect(edgeColor(tester), scheme.brandSuccess.withValues(alpha: 0.75));
    });
  });

  group('StandardInputField — behaviour', () {
    testWidgets(
      'validation error appears on Form.validate and clears on typing',
      (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(
          harness(
            StandardInputField(
              label: 'Email',
              keyboard: DsKeyboard.email,
              validator: (v) => DsValidators.email(v, message: 'Invalid email'),
            ),
            formKey: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        );

        expect(formKey.currentState!.validate(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Invalid email'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'juma@sokovibe.co.tz');
        await tester.pumpAndSettle();
        expect(find.text('Invalid email'), findsNothing);
        expect(formKey.currentState!.validate(), isTrue);
      },
    );

    testWidgets('keyboard intent strips non-digits from a number field', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const StandardInputField(
            label: 'Amount',
            keyboard: DsKeyboard.number,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '12ab34');
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1234',
      );
    });

    testWidgets('onChanged never emits zero-width characters', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(
        harness(StandardInputField(label: 'Name', onChanged: seen.add)),
      );

      await tester.enterText(find.byType(TextField), 'Ju\u200Bma');
      await tester.pump();

      expect(seen.last, 'Juma');
    });

    testWidgets('password toggle flips obscureText', (tester) async {
      await tester.pumpWidget(
        harness(
          const StandardInputField(
            label: 'Password',
            keyboard: DsKeyboard.password,
          ),
        ),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
    });

    testWidgets('clear button empties the controller and notifies onChanged', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'text');
      final seen = <String>[];
      await tester.pumpWidget(
        harness(
          StandardInputField(
            controller: controller,
            label: 'Search',
            clearable: true,
            onChanged: seen.add,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.cancel_rounded));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(seen.last, isEmpty);
      // The FormField value is re-synced, so a later validate sees the empty field.
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
    });
  });

  group('StandardInputField — dark theme', () {
    testWidgets('idle edge uses the dark hairline', (tester) async {
      await tester.pumpWidget(
        harness(
          const StandardInputField(label: 'Name'),
          brightness: Brightness.dark,
        ),
      );

      final scheme = Theme.of(
        tester.element(find.byType(StandardInputField)),
      ).colorScheme;
      expect(edgeColor(tester), scheme.hairline);
    });
  });

  group('DsValidators', () {
    test('email rejects malformed addresses', () {
      expect(DsValidators.email('juma@sokovibe.co.tz'), isNull);
      expect(DsValidators.email('juma@sokovibe'), isNotNull);
      expect(DsValidators.email(''), isNotNull);
    });

    test('phone accepts local and international Tanzanian formats', () {
      expect(DsValidators.phone('0714000000'), isNull);
      expect(DsValidators.phone('+255714000000'), isNull);
      expect(DsValidators.phone('071 400 0000'), isNull);
      expect(DsValidators.phone('12345'), isNotNull);
    });

    test('compose returns the first failure', () {
      final composed = DsValidators.compose([
        (v) => DsValidators.required(v, message: 'Required'),
        (v) => DsValidators.email(v, message: 'Invalid email'),
      ])!;
      expect(composed(''), 'Required');
      expect(composed('bad'), 'Invalid email');
      expect(composed('a@b.co'), isNull);
    });
  });
}
