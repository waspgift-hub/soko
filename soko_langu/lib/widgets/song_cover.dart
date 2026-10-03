import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/music_library_service.dart';

/// Cover art for a song, album or artist, read from the device.
///
/// The bytes are already inside the audio file (MediaStore/Android, Media
/// Library/iOS), so this needs no network and no extra permission. A track with
/// no embedded art falls back to a music glyph rather than a broken image box,
/// which is the difference between "this song has no cover" and "the app failed".
class SongCover extends StatelessWidget {
  final LocalSong? song;
  final Uint8List? bytes;
  final double size;
  final double radius;

  const SongCover({
    super.key,
    this.song,
    this.bytes,
    this.size = 48,
    this.radius = 8,
  });

  /// Builds straight from raw bytes, for an album/artist that has no single
  /// [LocalSong] of its own.
  const SongCover.raw({
    super.key,
    required this.bytes,
    this.size = 48,
    this.radius = 8,
  }) : song = null;

  @override
  Widget build(BuildContext context) {
    final art = bytes ?? song?.artwork;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );

    if (art == null || art.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.memory(
        art,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A corrupt embedded image falls back to the glyph instead of an
        // exception box in the middle of the list.
        errorBuilder: (context, error, stackTrace) => placeholder,
        gaplessPlayback: true,
      ),
    );
  }
}