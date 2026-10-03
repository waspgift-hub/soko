import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/music_library_service.dart';

LocalSong song(
  String id,
  String title, {
  String artist = 'Unknown',
  String album = '',
  int ms = 200000,
}) =>
    LocalSong(
      id: id,
      title: title,
      artist: artist,
      album: album,
      path: '/storage/$id.mp3',
      durationMs: ms,
    );

void main() {
  group('search', () {
    final library = [
      song('1', 'Shape of You', artist: 'Ed Sheeran', album: 'Divide'),
      song('2', 'Perfect', artist: 'Ed Sheeran', album: 'Divide'),
      song('3', 'Zuchu', artist: 'Diamond Platnumz', album: 'Ianza'),
      song('4', 'Unknown Track'),
    ];

    test('an empty query returns everything', () {
      expect(MusicLibraryService.search(library, '').length, 4);
      expect(MusicLibraryService.search(library, '   ').length, 4);
    });

    test('matches on title, case-insensitively', () {
      final r = MusicLibraryService.search(library, 'shape');
      expect(r.length, 1);
      expect(r.first.title, 'Shape of You');
    });

    test('matches on artist', () {
      final r = MusicLibraryService.search(library, 'ed sheeran');
      expect(r.length, 2);
    });

    test('matches on album', () {
      expect(MusicLibraryService.search(library, 'divide').length, 2);
    });

    test('matches a substring of a word', () {
      expect(MusicLibraryService.search(library, 'plat').single.title, 'Zuchu');
    });

    test('returns nothing for a song that is not there', () {
      expect(MusicLibraryService.search(library, 'bohemian'), isEmpty);
    });

    test('the placeholder "Unknown" artist is not a searchable value', () {
      // A user typing "unknown" wants a song called Unknown, not every track
      // whose metadata happens to be missing an artist.
      final r = MusicLibraryService.search(library, 'unknown');
      expect(r.length, 1);
      expect(r.single.title, 'Unknown Track');
    });
  });

  group('albumsOf', () {
    test('groups by album and artist', () {
      final albums = MusicLibraryService().albumsOf([
        song('1', 'A', artist: 'X', album: 'Album One'),
        song('2', 'B', artist: 'X', album: 'Album One'),
        song('3', 'C', artist: 'Y', album: 'Album Two'),
      ]);
      expect(albums.length, 2);
      final one = albums.firstWhere((a) => a.name == 'Album One');
      expect(one.songs.length, 2);
      expect(one.artist, 'X');
    });

    test('the same album name by different artists stays separate', () {
      final albums = MusicLibraryService().albumsOf([
        song('1', 'A', artist: 'X', album: 'Greatest Hits'),
        song('2', 'B', artist: 'Y', album: 'Greatest Hits'),
      ]);
      expect(albums.length, 2, reason: 'colliding them would mix two artists');
    });

    test('total duration is the sum of its tracks', () {
      final albums = MusicLibraryService().albumsOf([
        song('1', 'A', album: 'L', ms: 100000),
        song('2', 'B', album: 'L', ms: 150000),
      ]);
      expect(albums.single.duration, const Duration(milliseconds: 250000));
    });

    test('a track with no album is not dropped', () {
      final albums = MusicLibraryService().albumsOf([song('1', 'Loose')]);
      expect(albums.length, 1);
      expect(albums.single.name, 'Unknown album');
    });

    test('is sorted by name so the grid is stable', () {
      final albums = MusicLibraryService().albumsOf([
        song('1', 'A', album: 'Zebra'),
        song('2', 'B', album: 'Alpha'),
      ]);
      expect(albums.map((a) => a.name), ['Alpha', 'Zebra']);
    });
  });

  group('LocalSong', () {
    test('display fields hide the metadata placeholder', () {
      expect(song('1', 'T').displayArtist, '');
      expect(song('1', 'T', album: 'Unknown').displayAlbum, '');
      expect(song('1', 'T', artist: 'Ed').displayArtist, 'Ed');
    });
  });
}