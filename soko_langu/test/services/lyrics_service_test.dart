import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/lyrics_service.dart';

void main() {
  const parser = LrcParser();

  group('LrcParser', () {
    test('parses standard [mm:ss.xx] centisecond tags', () {
      final lines = parser.parse('[00:12.34]First line\n[01:05.50]Second line');
      expect(lines.length, 2);
      expect(lines[0].timestamp, const Duration(milliseconds: 12340));
      expect(lines[0].text, 'First line');
      expect(lines[1].timestamp, const Duration(minutes: 1, seconds: 5, milliseconds: 500));
      expect(lines[1].text, 'Second line');
    });

    test('parses [mm:ss] with no fractional part', () {
      final lines = parser.parse('[00:30]Chorus');
      expect(lines.single.timestamp, const Duration(seconds: 30));
    });

    test('parses 3-digit fractional part as milliseconds', () {
      final lines = parser.parse('[00:12.345]Line');
      expect(lines.single.timestamp, const Duration(milliseconds: 12345));
    });

    test('parses colon-separated fractional part', () {
      final lines = parser.parse('[00:12:50]Line');
      expect(lines.single.timestamp, const Duration(milliseconds: 12500));
    });

    test('expands a shared chorus into one entry per timestamp', () {
      // A chorus tagged at two points in the song is a single source line, but
      // it has to highlight twice or the second pass stays dim forever.
      final lines = parser.parse('[01:00.00][02:00.00]Chorus line');
      expect(lines.length, 2);
      expect(lines[0].timestamp, const Duration(minutes: 1));
      expect(lines[1].timestamp, const Duration(minutes: 2));
      expect(lines[0].text, 'Chorus line');
      expect(lines[1].text, 'Chorus line');
    });

    test('sorts lines that were supplied out of order', () {
      final lines = parser.parse('[01:00.00]Second\n[00:10.00]First');
      expect(lines[0].text, 'First');
      expect(lines[1].text, 'Second');
    });

    test('skips metadata tags and blank lines', () {
      const lrc = '[ar:Some Artist]\n[ti:Some Title]\n\n[00:05.00]Real line\n';
      final lines = parser.parse(lrc);
      expect(lines.length, 1);
      expect(lines.single.text, 'Real line');
    });

    test('keeps timestamped lines that have empty text', () {
      // Instrumental breaks are expressed as bare tags; dropping them would
      // stop the previous line staying lit through the whole break.
      final lines = parser.parse('[00:10.00]Lyric\n[00:20.00]');
      expect(lines.length, 2);
      expect(lines[1].text, '');
    });

    test('returns empty for empty, untimed and garbage input', () {
      expect(parser.parse(''), isEmpty);
      expect(parser.parse('   \n  '), isEmpty);
      expect(parser.parse('just some plain text\nwith no tags'), isEmpty);
      expect(parser.parse('[99]bad tag'), isEmpty);
    });

    test('handles CRLF and bare CR line endings', () {
      expect(parser.parse('[00:01.00]A\r\n[00:02.00]B\r[00:03.00]C').length, 3);
    });

    test('accepts hour-length timestamps', () {
      final lines = parser.parse('[100:00.00]Long track');
      expect(lines.single.timestamp, const Duration(minutes: 100));
    });
  });

  group('Lyrics.activeIndexAt', () {
    const synced = Lyrics(synced: [
      LyricLine(Duration(seconds: 10), 'one'),
      LyricLine(Duration(seconds: 20), 'two'),
      LyricLine(Duration(seconds: 30), 'three'),
    ]);

    test('returns -1 before the first line', () {
      expect(synced.activeIndexAt(const Duration(seconds: 5)), -1);
    });

    test('returns the first index at exactly the first timestamp', () {
      expect(synced.activeIndexAt(const Duration(seconds: 10)), 0);
    });

    test('holds a line until the next timestamp', () {
      expect(synced.activeIndexAt(const Duration(seconds: 19)), 0);
      expect(synced.activeIndexAt(const Duration(seconds: 20)), 1);
      expect(synced.activeIndexAt(const Duration(seconds: 29)), 1);
    });

    test('holds the last line past the end', () {
      expect(synced.activeIndexAt(const Duration(minutes: 9)), 2);
    });

    test('returns -1 when there are no synced lines', () {
      expect(Lyrics.empty.activeIndexAt(Duration.zero), -1);
      expect(const Lyrics(plain: ['a']).activeIndexAt(Duration.zero), -1);
    });
  });

  group('Lyrics', () {
    test('empty is distinguishable from loading', () {
      expect(Lyrics.empty.isEmpty, isTrue);
      expect(const Lyrics(plain: ['a']).isEmpty, isFalse);
      expect(const Lyrics(instrumental: true).isEmpty, isFalse);
    });

    test('hasSynced only when timed lines exist', () {
      expect(const Lyrics(plain: ['a']).hasSynced, isFalse);
      expect(
        const Lyrics(synced: [LyricLine(Duration.zero, 'a')]).hasSynced,
        isTrue,
      );
    });

    test('displayLines prefers synced text and falls back to plain', () {
      expect(const Lyrics(plain: ['a', 'b']).displayLines, ['a', 'b']);
      expect(
        const Lyrics(
          synced: [LyricLine(Duration.zero, 'synced')],
          plain: ['plain'],
        ).displayLines,
        ['synced'],
      );
    });
  });
}
