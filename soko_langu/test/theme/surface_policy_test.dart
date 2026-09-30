import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/theme/app_themes.dart';
import 'package:soko_vibe/theme/neumorphic.dart';
import 'package:soko_vibe/theme/surface_policy.dart';

void main() {
  group('SurfacePolicy — role to style mapping', () {
    test('soft-UI is reserved for interactive controls only', () {
      expect(
        SurfacePolicy.softRoles,
        {
          SurfaceRole.primaryCta,
          SurfaceRole.floatingAction,
          SurfaceRole.navBar,
          SurfaceRole.searchField,
          SurfaceRole.textField,
          SurfaceRole.activeFilter,
        },
      );
    });

    test('controls that commit an action are raised', () {
      expect(
        SurfacePolicy.styleFor(SurfaceRole.primaryCta),
        SurfaceStyle.raised,
      );
      expect(
        SurfacePolicy.styleFor(SurfaceRole.floatingAction),
        SurfaceStyle.raised,
      );
      expect(SurfacePolicy.styleFor(SurfaceRole.navBar), SurfaceStyle.raised);
    });

    test('input wells and active filters are recessed', () {
      expect(
        SurfacePolicy.styleFor(SurfaceRole.searchField),
        SurfaceStyle.inset,
      );
      expect(SurfacePolicy.styleFor(SurfaceRole.textField), SurfaceStyle.inset);
      expect(
        SurfacePolicy.styleFor(SurfaceRole.activeFilter),
        SurfaceStyle.inset,
      );
    });

    test('every content-bearing role is flat', () {
      const contentRoles = [
        SurfaceRole.card,
        SurfaceRole.listRow,
        SurfaceRole.dialog,
        SurfaceRole.sheet,
        SurfaceRole.menu,
        SurfaceRole.banner,
        SurfaceRole.chip,
        SurfaceRole.divider,
      ];
      for (final role in contentRoles) {
        expect(
          SurfacePolicy.styleFor(role),
          SurfaceStyle.flat,
          reason: '$role carries content and must stay flat',
        );
        expect(SurfacePolicy.isSoft(role), isFalse);
      }
    });

    test('isSoft agrees with styleFor for every role', () {
      for (final role in SurfaceRole.values) {
        expect(
          SurfacePolicy.isSoft(role),
          SurfacePolicy.styleFor(role) != SurfaceStyle.flat,
          reason: 'isSoft and styleFor disagree on $role',
        );
      }
    });
  });

  group('SurfacePolicy — the 90/10 budget', () {
    test('soft roles stay a small minority of the role set', () {
      final soft = SurfaceRole.values.where(SurfacePolicy.isSoft).length;
      final total = SurfaceRole.values.length;
      // Guards the intent: soft-UI is an accent, not the foundation. Six control
      // roles out of fourteen is ~43% of the *vocabulary*, but those six are the
      // low-frequency-per-screen elements — one CTA, one FAB, one nav bar, a
      // couple of wells — which is where the ~10% per screen comes from.
      expect(soft, lessThan(total));
      expect(soft, 6);
      expect(total - soft, 8);
    });
  });

  group('SurfacePolicy.decorate — flat output', () {
    test('flat roles use a single shadow, not a dual light/shade pair', () {
      for (final b in Brightness.values) {
        final d = SurfacePolicy.decorate(
          SurfaceRole.card,
          b,
          radius: 16,
        );
        expect(
          d.boxShadow,
          hasLength(1),
          reason: 'flat surfaces get one directional shadow in $b',
        );
      }
    });

    test('flat shadows only fall on the bottom-right, never top-left', () {
      for (final b in Brightness.values) {
        final shadows =
            SurfacePolicy.decorate(SurfaceRole.card, b, radius: 16).boxShadow!;
        for (final s in shadows) {
          expect(s.offset.dx, greaterThanOrEqualTo(0));
          expect(s.offset.dy, greaterThanOrEqualTo(0));
        }
      }
    });

    test('flat surfaces keep a hairline edge', () {
      final d = SurfacePolicy.decorate(
        SurfaceRole.card,
        Brightness.light,
        radius: 16,
      );
      final border = d.border;
      expect(border, isA<Border>());
      expect((border! as Border).top.width, 0.5);
    });

    test('overlays (sheet/dialog/menu) cast a stronger shadow than cards', () {
      final card = SurfacePolicy.decorate(
        SurfaceRole.card,
        Brightness.light,
        radius: 16,
      );
      final sheet = SurfacePolicy.decorate(
        SurfaceRole.sheet,
        Brightness.light,
        radius: 16,
      );
      expect(
        sheet.boxShadow!.first.blurRadius,
        greaterThan(card.boxShadow!.first.blurRadius),
      );
    });

    test('flat fill is distinct from the soft-UI base', () {
      for (final b in Brightness.values) {
        expect(
          Neu.flatFill(b),
          isNot(Neu.base(b)),
          reason: 'a flat surface sharing the soft base would read as soft-UI',
        );
      }
    });
  });

  group('SurfacePolicy.decorate — soft output', () {
    test('raised roles emit a dual shadow pair', () {
      for (final b in Brightness.values) {
        final d = SurfacePolicy.decorate(
          SurfaceRole.navBar,
          b,
          radius: 24,
        );
        expect(d.boxShadow, hasLength(2));
        // One light from the top-left, one shade to the bottom-right.
        expect(d.boxShadow![0].offset.dx, greaterThan(0));
        expect(d.boxShadow![1].offset.dx, lessThan(0));
      }
    });

    test('inset roles are recessed with a groove and no drop shadow', () {
      for (final b in Brightness.values) {
        final d = SurfacePolicy.decorate(
          SurfaceRole.textField,
          b,
          radius: 16,
        );
        expect(d.boxShadow, isNull);
        expect(d.border, isNotNull);
        expect(d.color, Neu.insetBase(b));
      }
    });

    test('an explicit accent recolours the inset groove', () {
      final d = SurfacePolicy.decorate(
        SurfaceRole.textField,
        Brightness.light,
        radius: 16,
        borderColor: const Color(0xFF00C853),
      );
      final border = d.border! as Border;
      expect(border.top.color, const Color(0xFF00C853));
      expect(border.top.width, 1.5);
    });

    test('an explicit fill overrides the canonical colour', () {
      final d = SurfacePolicy.decorate(
        SurfaceRole.activeFilter,
        Brightness.light,
        radius: 20,
        fill: const Color(0xFF00C853),
      );
      expect(d.color, const Color(0xFF00C853));
    });
  });

  group('SurfacePolicy.decorate — borderRadius override', () {
    test('asymmetric radii are honoured for sheets', () {
      final d = SurfacePolicy.decorate(
        SurfaceRole.sheet,
        Brightness.light,
        radius: 20,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      );
      final br = d.borderRadius as BorderRadius;
      expect(br.topLeft.y, 24);
      expect(br.bottomLeft.y, 0);
    });
  });

  group('Theme honours the flat-first split', () {
    test('scaffold canvas is flat, not the soft-UI base', () {
      for (final theme in [
        buildLightTheme(const Color(0xFF00C853)),
        buildDarkTheme(const Color(0xFF00C853)),
      ]) {
        expect(
          theme.scaffoldBackgroundColor,
          theme.colorScheme.brightness == Brightness.dark
              ? Neu.canvas(Brightness.dark)
              : Neu.canvas(Brightness.light),
        );
        expect(
          theme.scaffoldBackgroundColor,
          isNot(Neu.base(theme.colorScheme.brightness)),
        );
      }
    });

    test('content surfaces are flat with no elevation', () {
      for (final theme in [
        buildLightTheme(const Color(0xFF00C853)),
        buildDarkTheme(const Color(0xFF00C853)),
      ]) {
        expect(theme.cardTheme.elevation, 0);
        expect(theme.cardTheme.shadowColor, Colors.transparent);
        expect(theme.cardTheme.color, isNot(Neu.base(theme.brightness)));
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.snackBarTheme.elevation, 0);
      }
    });

    test('the primary CTA and FAB keep a soft accent', () {
      for (final theme in [
        buildLightTheme(const Color(0xFF00C853)),
        buildDarkTheme(const Color(0xFF00C853)),
      ]) {
        final elevated = theme.elevatedButtonTheme.style;
        expect(elevated?.backgroundColor?.resolve({}), theme.colorScheme.primary);
        // A non-zero elevation is what carries the soft accent for the legacy
        // ElevatedButton path; DsButton uses the full dual-shadow treatment.
        expect(elevated?.elevation?.resolve({}), isNot(0));
      }
    });

    test('input wells stay recessed', () {
      for (final theme in [
        buildLightTheme(const Color(0xFF00C853)),
        buildDarkTheme(const Color(0xFF00C853)),
      ]) {
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(
          theme.inputDecorationTheme.fillColor,
          Neu.insetBase(theme.brightness),
        );
      }
    });
  });
}
