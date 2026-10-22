import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:soko_vibe_music/screens/music_admin_dashboard_page.dart';
import 'package:soko_vibe_music/services/music_api.dart';

void main() {
  testWidgets('admin diagnostics dashboard explains checks and does not run them on open',
      (tester) async {
    var requestCount = 0;
    final api = MusicApi(
      baseUrl: 'https://music.example.test',
      client: MockClient((request) async {
        requestCount++;
        return http.Response('{"status":"healthy","jamendo":{"connected":true},"ai":{"configured":true}}', 200);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(MaterialApp(
      home: MusicAdminDashboardPage(api: api),
    ));

    expect(find.text('Music admin dashboard'), findsOneWidget);
    expect(find.text('Backend health'), findsOneWidget);
    expect(find.text('Jamendo search'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('AI lyrics generation'), findsOneWidget);
    expect(find.text('Not tested yet'), findsWidgets);
    expect(requestCount, 0);
  });
}
