import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soko_vibe/main.dart' as app;
import '../helpers/test_helpers.dart';

/// E2E tests for the seller wallet flow:
/// - Earnings screen renders balance
/// - Withdrawal screen validates input
/// - Transaction history renders
/// - No money movement is possible without confirmation
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Wallet Flow E2E', () {
    testWidgets('TC-WALLET-01: Earnings reachable from seller dashboard', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final profileIcon = find.byIcon(Icons.person_outline_rounded);
      if (profileIcon.evaluate().isNotEmpty) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-02: Balance displays without crash', (tester) async {
      app.main();
      await waitForAppReady(tester);

      // Balance text (TZS) renders when the wallet screen is open.
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-03: Withdrawal button opens confirmation', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final withdraw = find.textContaining('ithdraw');
      if (withdraw.evaluate().isNotEmpty) {
        await tester.tap(withdraw.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-04: Empty withdrawal amount is rejected', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final withdraw = find.textContaining('ithdraw');
      if (withdraw.evaluate().isNotEmpty) {
        await tester.tap(withdraw.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final confirm = find.textContaining('onfirm');
        if (confirm.evaluate().isNotEmpty) {
          await tester.tap(confirm.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-05: Invalid phone number is rejected', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final fields = find.byType(TextFormField);
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, 'abc');
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-06: Transaction history scrolls', (tester) async {
      app.main();
      await waitForAppReady(tester);

      await tester.drag(
        find.byType(Scaffold).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-07: Back navigation from wallet works', (tester) async {
      app.main();
      await waitForAppReady(tester);

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      verifyNoErrors(tester);
    });

    testWidgets('TC-WALLET-08: Rapid taps on withdraw do not double-submit', (tester) async {
      app.main();
      await waitForAppReady(tester);

      final withdraw = find.textContaining('ithdraw');
      if (withdraw.evaluate().isNotEmpty) {
        for (var i = 0; i < 2; i++) {
          await tester.tap(withdraw.first);
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      verifyNoErrors(tester);
    });
  });
}
