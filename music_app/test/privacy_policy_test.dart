import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe_music/main.dart';

void main() {
  testWidgets('privacy policy page presents the current data-handling notice', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyPage()));

    expect(find.text('SokoVibe Music Privacy Policy'), findsOneWidget);
    expect(find.text('Information handled'), findsOneWidget);
    expect(
      find.textContaining('Cloudflare processes network information'),
      findsOneWidget,
    );
  });
}
