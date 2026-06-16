import 'dart:convert';
import 'dart:typed_data';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/audio_item.dart';

class AudioContentService {
  static final AudioContentService _instance = AudioContentService._();
  factory AudioContentService() => _instance;
  AudioContentService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Check if storage/audio permission is granted
  Future<bool> hasPermission() async {
    try {
      return await _audioQuery.permissionsStatus();
    } catch (_) {
      return false;
    }
  }

  /// Request storage/audio permission
  Future<bool> requestPermission() async {
    try {
      return await _audioQuery.permissionsRequest();
    } catch (_) {
      return false;
    }
  }

  /// Get songs from device
  Future<List<AudioItem>> getDeviceSongs() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
      return songs.map(_songToItem).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get artwork for a song as Uint8List
  Future<Uint8List?> getArtwork(int songId, ArtworkType type) async {
    try {
      return await _audioQuery.queryArtwork(songId, type, size: 200, quality: 100);
    } catch (_) {
      return null;
    }
  }

  /// Get artwork as a data URI string for use in MediaItem.artUri
  Future<String?> getArtworkDataUri(int songId, ArtworkType type) async {
    try {
      final bytes = await getArtwork(songId, type);
      if (bytes == null) return null;
      final b64 = base64Encode(bytes);
      return 'data:image/jpeg;base64,$b64';
    } catch (_) {
      return null;
    }
  }

  AudioItem _songToItem(SongModel s) => AudioItem(
        id: s.id.toString(),
        title: s.title,
        artist: s.artist ?? 'Unknown',
        url: s.uri ?? s.data,
        imageUrl: null,
        duration: Duration(milliseconds: s.duration ?? 0),
      );

  static List<AudioItem> get sampleSongs => _sampleSongs;

  static String _artUrl(String label) =>
      'https://ui-avatars.com/api/?name=$label&background=40916C&color=fff&size=200&bold=true';

  static final List<AudioItem> _sampleSongs = [
    AudioItem(
      id: '1',
      title: 'Muziki wa Asili',
        artist: 'Soko Vibe Band',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      imageUrl: _artUrl('Soko+Vibe'),
    ),
    AudioItem(
      id: '2',
      title: 'Sauti ya Tanzania',
      artist: 'Malkia wa Nyimbo',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      imageUrl: _artUrl('Malkia'),
    ),
    AudioItem(
      id: '3',
      title: 'Upendo wa Kweli',
      artist: 'Jamaa wa Muziki',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      imageUrl: _artUrl('Jamaa'),
    ),
    AudioItem(
      id: '4',
      title: 'Nchi Yetu',
      artist: 'Wasana Nyimbo',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
      imageUrl: _artUrl('Wasana'),
    ),
    AudioItem(
      id: '5',
      title: 'Furaha Mitaani',
      artist: 'Dawati Band',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
      imageUrl: _artUrl('Dawati'),
    ),
    AudioItem(
      id: '6',
      title: 'Lala Salama',
      artist: 'Sauti Safi',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
      imageUrl: _artUrl('Sauti+Safi'),
    ),
    AudioItem(
      id: '7',
        title: 'Soko Vibe Theme',
      artist: 'Gift & Praygod',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
      imageUrl: _artUrl('Gift+Praygod'),
    ),
    AudioItem(
      id: '8',
      title: 'Kazi ya Mikono',
      artist: 'Fundi Arts',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
      imageUrl: _artUrl('Fundi+Arts'),
    ),
  ];
}
