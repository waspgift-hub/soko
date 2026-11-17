import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/theme/app_themes.dart';
import 'package:soko_vibe/theme/neumorphic.dart';
import 'package:soko_vibe/theme/soko_palette.dart';
import 'package:soko_vibe/widgets/ds/ds_button.dart';

/// WCAG 2.1 relative-contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('SokoPalette — official brand values', () {
    test('light palette matches the spec hex values', () {
      expect(SokoPalette.lightPrimary, const Color(0xFF0B6B3A));
      expect(SokoPalette.lightPrimaryDark, const Color(0xFF084D2B));
      expect(SokoPalette.lightPrimaryLight, const Color(0xFFE9F5ED));
      expect(SokoPalette.lightBackground, const Color(0xFFF7F8F7));
      expect(SokoPalette.lightCard, const Color(0xFFFFFFFF));
      expect(SokoPalette.lightTextPrimary, const Color(0xFF17211B));
      expect(SokoPalette.lightTextSecondary, const Color(0xFF5F6B63));
      expect(SokoPalette.lightTextDisabled, const Color(0xFF9AA59D));
      expect(SokoPalette.lightBorder, const Color(0xFFE2E8E3));
      expect(SokoPalette.lightDivider, const Color(0xFFEDF0ED));
    });

    test('dark palette matches the spec hex values', () {
      expect(SokoPalette.darkBackground, const Color(0xFF000000));
      expect(SokoPalette.darkSurface, const Color(0xFF101713));
      expect(SokoPalette.darkSurfaceSecondary, const Color(0xFF18221B));
      expect(SokoPalette.darkPrimary, const Color(0xFF32B86C));
      expect(SokoPalette.darkPrimaryDark, const Color(0xFF228B50));
      expect(SokoPalette.darkPrimaryLight, const Color(0xFF193C29));
      expect(SokoPalette.darkTextPrimary, const Color(0xFFFFFFFF));
      expect(SokoPalette.darkTextSecondary, const Color(0xFFB3C4B8));
      expect(SokoPalette.darkTextDisabled, const Color(0xFF78847B));
      expect(SokoPalette.darkBorder, const Color(0xFF29352D));
      expect(SokoPalette.darkDivider, const Color(0xFF202A23));
      expect(SokoPalette.amber, const Color(0xFFF4B740));
    });
  });

  group('buildLightTheme', () {
    final theme = buildLightTheme(SokoPalette.lightPrimary);
    final cs = theme.colorScheme;

    test('maps the light canvas, card and brand ramp', () {
      expect(theme.scaffoldBackgroundColor, SokoPalette.lightBackground);
      expect(cs.surface, SokoPalette.lightCard);
      expect(cs.primary, SokoPalette.lightPrimary);
      expect(cs.onPrimary, SokoPalette.onLightPrimary);
      expect(cs.onSurface, SokoPalette.lightTextPrimary);
      expect(cs.onSurfaceVariant, SokoPalette.lightTextSecondary);
      expect(cs.outlineVariant, SokoPalette.lightBorder);
      expect(cs.primaryContainer, SokoPalette.lightPrimaryLight);
      expect(cs.onPrimaryContainer, SokoPalette.lightPrimaryDark);
    });

    test('secondary button is transparent with a green edge and label', () {
      final style = theme.outlinedButtonTheme.style!;
      expect(style.backgroundColor?.resolve({}), Colors.transparent);
      expect(style.foregroundColor?.resolve({}), SokoPalette.lightPrimary);
      expect(style.side?.resolve({})?.color, SokoPalette.lightPrimary);
    });

    test('selected chips use the light-green container, not the fill', () {
      expect(theme.chipTheme.selectedColor, SokoPalette.lightPrimaryLight);
      expect(theme.chipTheme.backgroundColor, SokoPalette.lightDivider);
    });

    test('bottom navigation selection is green, unselected is secondary', () {
      final labelStyle = theme.navigationBarTheme.labelTextStyle!;
      expect(labelStyle.resolve({WidgetState.selected})?.color, SokoPalette.lightPrimary);
      expect(labelStyle.resolve({})?.color, SokoPalette.lightTextSecondary);
    });
  });

  group('buildDarkTheme', () {
    final theme = buildDarkTheme(SokoPalette.darkPrimary);
    final cs = theme.colorScheme;

    test('uses true black canvas and raised dark surfaces', () {
      expect(theme.scaffoldBackgroundColor, SokoPalette.darkBackground);
      expect(cs.surface, SokoPalette.darkSurface);
      expect(cs.primary, SokoPalette.darkPrimary);
      expect(cs.onPrimary, SokoPalette.onDarkPrimary);
      expect(cs.onSurface, SokoPalette.darkTextPrimary);
      expect(cs.onSurfaceVariant, SokoPalette.darkTextSecondary);
      expect(cs.outlineVariant, SokoPalette.darkDivider);
    });

    test('neumorphic tokens use the dark card and canvas', () {
      expect(Neu.canvas(Brightness.dark), SokoPalette.darkBackground);
      expect(Neu.flatFill(Brightness.dark), SokoPalette.darkSurface);
      expect(Neu.base(Brightness.dark), SokoPalette.darkSurfaceSecondary);
    });
  });

  group('WCAG 2.1 AA contrast', () {
    test('body text on cards reaches 4.5:1 in both themes', () {
      expect(
        contrast(SokoPalette.lightTextPrimary, SokoPalette.lightCard),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(SokoPalette.lightTextSecondary, SokoPalette.lightCard),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(SokoPalette.darkTextPrimary, SokoPalette.darkSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(SokoPalette.darkTextSecondary, SokoPalette.darkSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('primary CTA labels reach 4.5:1', () {
      expect(
        contrast(SokoPalette.onLightPrimary, SokoPalette.lightPrimary),
        greaterThanOrEqualTo(4.5),
      );
      // The bright dark-mode green forces near-black onPrimary; white would
      // only reach 2.6:1.
      expect(
        contrast(SokoPalette.onDarkPrimary, SokoPalette.darkPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(Colors.white, SokoPalette.darkPrimary), lessThan(4.5));
    });

    test('control outlines reach the 3:1 non-text requirement', () {
      expect(
        contrast(SokoPalette.lightTextSecondary, SokoPalette.lightCard),
        greaterThanOrEqualTo(3),
      );
      expect(
        contrast(SokoPalette.darkTextDisabled, SokoPalette.darkSurface),
        greaterThanOrEqualTo(3),
      );
    });

    test('semantic status colours stay legible on their own surfaces', () {
      expect(contrast(SokoPalette.lightError, SokoPalette.lightCard), greaterThanOrEqualTo(4.5));
      expect(contrast(SokoPalette.lightWarning, SokoPalette.lightCard), greaterThanOrEqualTo(4.5));
      expect(contrast(SokoPalette.darkError, SokoPalette.darkSurface), greaterThanOrEqualTo(4.5));
      expect(contrast(SokoPalette.darkWarning, SokoPalette.darkSurface), greaterThanOrEqualTo(4.5));
    });
  });

  group('DsButton brand surfaces', () {
    testWidgets('primary is the green fill with its on-brand label', (tester) async {
      for (final theme in [
        buildLightTheme(SokoPalette.lightPrimary),
        buildDarkTheme(SokoPalette.darkPrimary),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: DsButton(label: 'Pay', onPressed: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final box = tester.widget<DecoratedBox>(
          find.descendant(of: find.byType(DsButton), matching: find.byType(DecoratedBox)).first,
        );
        expect((box.decoration as BoxDecoration).color, theme.colorScheme.primary);
        expect(tester.widget<Text>(find.text('Pay')).style?.color, theme.colorScheme.onPrimary);
      }
    });

    testWidgets('secondary is light-green / dark-green, never neutral grey', (tester) async {
      for (final theme in [
        buildLightTheme(SokoPalette.lightPrimary),
        buildDarkTheme(SokoPalette.darkPrimary),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: DsButton(variant: DsButtonVariant.secondary, label: 'Cancel', onPressed: () {}),
            ),
          ),
        );
        // MaterialApp cross-fades between themes, so the first frame still
        // carries the previous palette; settle before reading the decoration.
        await tester.pumpAndSettle();

        final box = tester.widget<DecoratedBox>(
          find.descendant(of: find.byType(DsButton), matching: find.byType(DecoratedBox)).first,
        );
        expect((box.decoration as BoxDecoration).color, theme.colorScheme.primaryContainer);
        expect(
          tester.widget<Text>(find.text('Cancel')).style?.color,
          theme.colorScheme.onPrimaryContainer,
        );
      }
    });
  });
}
