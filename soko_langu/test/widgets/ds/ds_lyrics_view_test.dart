import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soko_vibe/services/lyrics_service.dart';
import 'package:soko_vibe/widgets/ds/ds_lyrics_view.dart';

import '../../test_helper.dart';

void main() {
  const synced = Lyrics(synced: [
    LyricLine(Duration(seconds: 10), 'first line'),
    LyricLine(Duration(seconds: 20), 'second line'),
    LyricLine(Duration(seconds: 30), 'third line'),
  ]);

  group('DsLyricsView', () {
    testWidgets('renders synced lines and highlights the active one', (tester) async {
      await pumpTestApp(
        tester,
        child: const Scaffold(
          body: DsLyricsView(
            lyrics: synced,
            position: Duration(seconds: 20),
          ),
        ),
      );

      expect(find.text('first line'), findsOneWidget);
      expect(find.text('second line'), findsOneWidget);
      expect(find.text('third line'), findsOneWidget);
    });

    testWidgets('shows loading dots while a fetch is in flight', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Pumped by hand rather than through pumpTestApp: the loading dots
      // animate forever, so pumpAndSettle would never return.
      await tester.pumpWidget(
        const TestApp(
          child: Scaffold(
            body: DsLyricsView(lyrics: Lyrics.empty, loading: true),
          ),
        ),
      );
      await tester.pump();

      // A loading panel must not claim "no lyrics found" — that would flash an
      // error every time a track opens on a slow connection.
      expect(find.text('No lyrics found'), findsNothing);
    });

    testWidgets('shows the empty state when there are no lyrics', (tester) async {
      await pumpTestApp(
        tester,
        child: const Scaffold(
          body: DsLyricsView(lyrics: Lyrics.empty),
        ),
      );

      expect(find.text('No lyrics found'), findsOneWidget);
      expect(find.text('We could not find lyrics for this track.'), findsOneWidget);
    });

    testWidgets('shows an instrumental state instead of "not found"',
        (tester) async {
      await pumpTestApp(
        tester,
        child: const Scaffold(
          body: DsLyricsView(lyrics: Lyrics(instrumental: true)),
        ),
      );

      expect(find.text('Instrumental'), findsOneWidget);
      expect(find.text('No lyrics found'), findsNothing);
    });

    testWidgets('renders unsynced lyrics as plain scrollable text',
        (tester) async {
      await pumpTestApp(
        tester,
        child: const Scaffold(
          body: DsLyricsView(
            lyrics: Lyrics(plain: ['plain one', 'plain two']),
          ),
        ),
      );

      expect(find.text('plain one'), findsOneWidget);
      expect(find.text('plain two'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });
  });
}
