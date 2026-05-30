import 'package:flutter_test/flutter_test.dart';
import 'package:soko_langu/models/music_playlist.dart';

void main() {
  group('PlaylistSong', () {
    test('fromPath creates song with path only', () {
      final song = PlaylistSong.fromPath('/music/song.mp3');
      expect(song.path, '/music/song.mp3');
      expect(song.title, null);
      expect(song.artist, null);
    });

    test('toJson serializes correctly', () {
      final song = PlaylistSong(path: '/a.mp3', title: 'Song', artist: 'Artist');
      final json = song.toJson();
      expect(json['path'], '/a.mp3');
      expect(json['title'], 'Song');
      expect(json['artist'], 'Artist');
    });

    test('toJson omits null title and artist', () {
      final song = PlaylistSong(path: '/a.mp3');
      final json = song.toJson();
      expect(json.containsKey('title'), false);
      expect(json.containsKey('artist'), false);
    });

    test('fromJson restores full song', () {
      final song = PlaylistSong.fromJson({
        'path': '/a.mp3',
        'title': 'Title',
        'artist': 'Artist',
      });
      expect(song.path, '/a.mp3');
      expect(song.title, 'Title');
      expect(song.artist, 'Artist');
    });

    test('fromJson handles missing optional fields', () {
      final song = PlaylistSong.fromJson({'path': '/a.mp3'});
      expect(song.path, '/a.mp3');
      expect(song.title, null);
      expect(song.artist, null);
    });
  });

  group('MusicPlaylist', () {
    test('constructor sets fields', () {
      final songs = [PlaylistSong(path: '/a.mp3')];
      final pl = MusicPlaylist(name: 'My Playlist', songs: songs);
      expect(pl.name, 'My Playlist');
      expect(pl.songs, songs);
    });

    test('songPaths returns list of paths', () {
      final pl = MusicPlaylist(name: 'P', songs: [
        PlaylistSong(path: '/a.mp3'),
        PlaylistSong(path: '/b.mp3'),
      ]);
      expect(pl.songPaths, ['/a.mp3', '/b.mp3']);
    });

    test('toJson serializes correctly', () {
      final pl = MusicPlaylist(name: 'Favorites', songs: [
        PlaylistSong(path: '/a.mp3', title: 'A'),
      ]);
      final json = pl.toJson();
      expect(json['name'], 'Favorites');
      expect(json['songs'], isA<List>());
      expect((json['songs'] as List).length, 1);
      expect((json['songs'] as List).first['path'], '/a.mp3');
    });

    test('fromJson parses songs as list of maps', () {
      final pl = MusicPlaylist.fromJson({
        'name': 'Test',
        'songs': [
          {'path': '/a.mp3', 'title': 'A'},
          {'path': '/b.mp3', 'title': 'B'},
        ],
      });
      expect(pl.name, 'Test');
      expect(pl.songs.length, 2);
      expect(pl.songs[0].path, '/a.mp3');
      expect(pl.songs[0].title, 'A');
    });

    test('fromJson parses songs as list of strings', () {
      final pl = MusicPlaylist.fromJson({
        'name': 'Test',
        'songs': ['/a.mp3', '/b.mp3'],
      });
      expect(pl.songs.length, 2);
      expect(pl.songs[0].path, '/a.mp3');
      expect(pl.songs[0].title, null);
    });

    test('fromJson falls back to songPaths key', () {
      final pl = MusicPlaylist.fromJson({
        'name': 'Legacy',
        'songPaths': ['/old1.mp3', '/old2.mp3'],
      });
      expect(pl.songs.length, 2);
      expect(pl.songs[0].path, '/old1.mp3');
    });

    test('fromJson returns empty songs when no data', () {
      final pl = MusicPlaylist.fromJson({'name': 'Empty'});
      expect(pl.songs, []);
    });
  });
}
