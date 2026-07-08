import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/audio_item.dart';

class AudioContentService {
  static final AudioContentService _instance = AudioContentService._();
  factory AudioContentService() => _instance;
  AudioContentService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<bool> hasPermission() async {
    try {
      return await _audioQuery.permissionsStatus();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _audioQuery.permissionsRequest();
    } catch (_) {
      return false;
    }
  }

  Future<List<AudioItem>> getDeviceSongs() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      return songs.map(songToItem).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<AlbumModel>> getAlbums() async {
    try {
      return await _audioQuery.queryAlbums(
        sortType: AlbumSortType.ALBUM,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<ArtistModel>> getArtists() async {
    try {
      return await _audioQuery.queryArtists(
        sortType: ArtistSortType.ARTIST,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<GenreModel>> getGenres() async {
    try {
      return await _audioQuery.queryGenres(
        sortType: GenreSortType.GENRE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<SongModel>> getAlbumSongs(int albumId) async {
    try {
      return await _audioQuery.queryAudiosFrom(
        AudiosFromType.ALBUM_ID,
        albumId,
        orderType: OrderType.ASC_OR_SMALLER,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<SongModel>> getArtistSongs(int artistId) async {
    try {
      return await _audioQuery.queryAudiosFrom(
        AudiosFromType.ARTIST,
        artistId,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<SongModel>> getGenreSongs(int genreId) async {
    try {
      return await _audioQuery.queryAudiosFrom(
        AudiosFromType.GENRE,
        genreId,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<SongModel>> getRecentlyAdded() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      return songs.take(50).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<SongModel>> getFolderSongs(String folderPath) async {
    try {
      final allSongs = await getDeviceSongs();
      return allSongs
          .where((s) => s.url.contains(folderPath))
          .map((a) => SongModel(<String, dynamic>{
                '_id': int.tryParse(a.id) ?? 0,
                '_data': a.url,
                '_display_name': a.title,
                'title': a.title,
                'artist': a.artist,
                'duration': a.duration.inMilliseconds,
              }))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Uint8List?> getArtwork(int songId, ArtworkType type) async {
    try {
      return await _audioQuery.queryArtwork(
        songId, type, size: 300, quality: 100,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> getArtworkDataUri(int songId, ArtworkType type) async {
    try {
      final bytes = await getArtwork(songId, type);
      if (bytes == null) return null;
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  AudioItem songToItem(SongModel s) => AudioItem(
        id: s.id.toString(),
        title: s.title,
        artist: s.artist ?? 'Unknown',
        url: 'content://media/external/audio/media/${s.id}',
        imageUrl: null,
        duration: Duration(milliseconds: s.duration ?? 0),
      );

  static List<AudioItem> get sampleSongs => _sampleSongs;

  static String _artUrl(String label) =>
      'https://ui-avatars.com/api/?name=$label&background=40916C&color=fff&size=200&bold=true';

  static final List<AudioItem> _sampleSongs = [
    AudioItem(id: '1', title: 'Muziki wa Asili', artist: 'Soko Vibe Band',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        imageUrl: _artUrl('Soko+Vibe')),
    AudioItem(id: '2', title: 'Sauti ya Tanzania', artist: 'Malkia wa Nyimbo',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        imageUrl: _artUrl('Malkia')),
    AudioItem(id: '3', title: 'Upendo wa Kweli', artist: 'Jamaa wa Muziki',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
        imageUrl: _artUrl('Jamaa')),
    AudioItem(id: '4', title: 'Nchi Yetu', artist: 'Wasana Nyimbo',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
        imageUrl: _artUrl('Wasana')),
    AudioItem(id: '5', title: 'Furaha Mitaani', artist: 'Dawati Band',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
        imageUrl: _artUrl('Dawati')),
    AudioItem(id: '6', title: 'Lala Salama', artist: 'Sauti Safi',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
        imageUrl: _artUrl('Sauti+Safi')),
    AudioItem(id: '7', title: 'Soko Vibe Theme', artist: 'Gift & Praygod',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
        imageUrl: _artUrl('Gift+Praygod')),
    AudioItem(id: '8', title: 'Kazi ya Mikono', artist: 'Fundi Arts',
        url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
        imageUrl: _artUrl('Fundi+Arts')),
  ];

  static Future<List<FirestoreYoutubeSong>> getFirestoreYoutubeSongs() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('youtubeSongs')
          .orderBy('title')
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return FirestoreYoutubeSong(
          docId: doc.id,
          videoId: data['videoId'] as String? ?? '',
          title: data['title'] as String? ?? 'Unknown',
          artist: data['artist'] as String? ?? 'Unknown',
          thumbnailUrl: data['thumbnailUrl'] as String? ?? '',
          durationSeconds: data['duration'] as int? ?? 0,
        );
      }).where((s) => s.videoId.isNotEmpty).toList();
    } catch (e) {
      debugPrint('getFirestoreYoutubeSongs error: $e');
      return [];
    }
  }
}

class FirestoreYoutubeSong {
  final String docId;
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final int durationSeconds;

  FirestoreYoutubeSong({
    required this.docId,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.durationSeconds,
  });

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$videoId';
  Duration get duration => Duration(seconds: durationSeconds);

  AudioItem toAudioItem() => AudioItem(
        id: 'yt_firestore_$docId',
        title: title,
        artist: artist,
        url: youtubeUrl,
        imageUrl: thumbnailUrl.isNotEmpty ? thumbnailUrl : null,
        duration: duration,
        youtubeVideoId: videoId,
      );

  static Future<List<FirestoreYoutubeSong>> fetchAll() =>
      AudioContentService.getFirestoreYoutubeSongs();
}
