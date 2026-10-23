import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_music/main.dart';

void main() {
  testWidgets('privacy policy page explains current data handling', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));

    expect(find.text('SokoVibe Music Privacy Policy'), findsOneWidget);
    expect(find.text('Information handled'), findsOneWidget);
    expect(find.text('Accounts, ads and payments'), findsOneWidget);
    expect(find.text('Service providers and retention'), findsOneWidget);
    expect(find.textContaining('support@sokovibe.co.tz'), findsOneWidget);
  });
}
