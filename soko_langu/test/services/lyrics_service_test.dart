import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/lyrics_service.dart';

// The synced viewer highlights whatever `activeIndexAt` returns, so a wrong
// millisecond is a wrong line on screen. These pin the parsing arithmetic and
// the boundary behaviour.
void main() {
  const parser = LrcParser();

  group('LrcParser', () {
    test('reads a standard centisecond timestamp', () {
      final lines = parser.parse('[00:09.69] First\n[00:12.18] Second');
      expect(lines.length, 2);
      expect(lines[0].timestamp, const Duration(milliseconds: 9690));
      expect(lines[0].text, 'First');
      expect(lines[1].timestamp, const Duration(milliseconds: 12180));
    });

    test('expands a line carrying several timestamps', () {
      // A shared chorus is written once with several start times.
      final lines = parser.parse('[00:10.00][01:10.00][02:10.00] Chorus');
      expect(lines.length, 3);
      expect(lines.every((l) => l.text == 'Chorus'), isTrue);
      expect(lines[2].timestamp, const Duration(minutes: 2, seconds: 10));
    });

    test('skips metadata tags', () {
      final lines = parser.parse('[ar:Artist]\n[ti:Title]\n[00:03.00] Real');
      expect(lines.length, 1);
      expect(lines[0].text, 'Real');
    });

    test('an offset tag shifts every line earlier', () {
      final plain = parser.parse('[00:10.00] line');
      final shifted = parser.parse('[offset:+2000]\n[00:10.00] line');
      // The provider says "these lyrics run 2s late", so the 10s line is due at 8s.
      expect(
        shifted.single.timestamp,
        Duration(milliseconds: plain.single.timestamp.inMilliseconds - 2000),
      );
    });

    test('a negative offset shifts them later', () {
      final lines = parser.parse('[offset:-1000]\n[00:10.00] line');
      expect(lines.single.timestamp, const Duration(milliseconds: 11000));
    });

    test('sorts out-of-order lines', () {
      final lines = parser.parse('[00:30.00] later\n[00:10.00] earlier');
      expect(lines.first.text, 'earlier');
    });

    test('garbage in yields nothing rather than throwing', () {
      expect(parser.parse(''), isEmpty);
      expect(parser.parse('   \n  '), isEmpty);
      expect(parser.parse('no timestamps here'), isEmpty);
    });
  });

  group('Lyrics.activeIndexAt', () {
    final lyrics = Lyrics(
      synced: parser.parse('[00:00.00] one\n[00:10.00] two\n[00:20.00] three'),
    );

    test('finds the active line', () {
      expect(lyrics.activeIndexAt(const Duration(seconds: 1)), 0);
      expect(lyrics.activeIndexAt(const Duration(seconds: 12)), 1);
      expect(lyrics.activeIndexAt(const Duration(seconds: 25)), 2);
    });

    test('returns -1 before the first line', () {
      final late = Lyrics(synced: parser.parse('[00:30.00] only'));
      expect(late.activeIndexAt(Duration.zero), -1);
    });

    test('stays on the last line past the end', () {
      expect(lyrics.activeIndexAt(const Duration(minutes: 5)), 2);
    });

    test('unsynced-only lyrics never highlight', () {
      final plain = Lyrics(plain: const ['a', 'b']);
      expect(plain.activeIndexAt(const Duration(seconds: 30)), -1);
      expect(plain.hasSynced, isFalse);
    });

    test('empty lyrics are empty, not broken', () {
      expect(Lyrics.empty.isEmpty, isTrue);
      expect(Lyrics.empty.activeIndexAt(const Duration(seconds: 5)), -1);
      expect(Lyrics.empty.displayLines, isEmpty);
    });
  });

  group('Lyrics.displayLines', () {
    test('prefers the synced text when there is any', () {
      final lyrics = Lyrics(
        synced: const LrcParser().parse('[00:01.00] synced line'),
        plain: const ['plain line'],
      );
      expect(lyrics.displayLines, ['synced line']);
    });

    test('falls back to plain text', () {
      final lyrics = Lyrics(plain: const ['plain line']);
      expect(lyrics.displayLines, ['plain line']);
    });
  });
}