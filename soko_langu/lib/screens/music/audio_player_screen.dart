import 'dart:async';

import 'package:flutter/material.dart';

import '../../extensions/context_tr.dart';
import '../../services/lyrics_service.dart';
import '../../services/profile_media_controller.dart';
import '../../services/profile_media_session.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ds/ds.dart';

/// Full-screen audio player: artwork or synced lyrics, transport controls,
/// seek bar, and the queue.
///
/// Reads the shared session rather than owning playback, so opening or
/// closing this screen never interrupts what the mini player is doing.
class AudioPlayerScreen extends StatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  ProfileMediaController get _media => ProfileMediaSession.instance.controller;

  final LyricsService _lyricsService = LyricsService();

  StreamSubscription<int>? _indexSub;
  StreamSubscription<Duration>? _durationSub;

  Lyrics _lyrics = Lyrics.empty;
  bool _loadingLyrics = false;
  String? _lyricsForId;
  bool _showLyrics = false;

  Duration _dragPosition = Duration.zero;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _indexSub = _media.indexStream.listen((_) => _syncLyrics());
    _durationSub = _media.durationStream.listen((_) => _syncLyrics());
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLyrics());
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    _durationSub?.cancel();
    _lyricsService.dispose();
    super.dispose();
  }

  /// Lyrics are keyed on the track id: skipping back and forth must not
  /// re-hit the network for a track already fetched this session.
  void _syncLyrics() {
    final item = _media.current;
    if (item == null || !item.isAudio) {
      if (_lyricsForId != null) {
        setState(() {
          _lyrics = Lyrics.empty;
          _lyricsForId = null;
          _showLyrics = false;
        });
      }
      return;
    }
    if (_lyricsForId == item.id || _loadingLyrics) return;
    _load(item);
  }

  Future<void> _load(ProfileMediaItem item) async {
    final (track, artist) = _splitTitleArtist(item);
    setState(() {
      _loadingLyrics = true;
      _lyricsForId = item.id;
      _lyrics = Lyrics.empty;
    });
    final result = await _lyricsService.fetch(
      track: track,
      artist: artist,
      album: item.album,
      duration: item.duration,
    );
    if (!mounted || _lyricsForId != item.id) return;
    setState(() {
      _loadingLyrics = false;
      _lyrics = result;
    });
  }

  /// Local songs arrive as "title - artist"; YouTube entries have no artist
  /// field. LRCLIB matches far better when the two are separated.
  static (String, String) _splitTitleArtist(ProfileMediaItem item) {
    if (item.artist.isNotEmpty) return (item.title, item.artist);
    const sep = ' - ';
    final at = item.title.lastIndexOf(sep);
    if (at > 0 && at + sep.length < item.title.length) {
      return (
        item.title.substring(0, at).trim(),
        item.title.substring(at + sep.length).trim(),
      );
    }
    return (item.title, '');
  }

  static String _clock(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _media.current;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('now_playing'))),
        body: DsEmptyState(
          icon: Icons.music_off_outlined,
          title: context.tr('no_music'),
          centered: true,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('now_playing')),
        actions: [
          IconButton(
            tooltip: context.tr('up_next'),
            onPressed: _media.queue.length > 1 ? _openQueue : null,
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize =
                (constraints.maxHeight * 0.42).clamp(160.0, 420.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s6,
                AppSpacing.s2,
                AppSpacing.s6,
                AppSpacing.s6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: artworkSize,
                    child: _showLyrics
                        ? _buildLyrics()
                        : _buildArtwork(item, artworkSize),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  if (_showLyrics)
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _showLyrics = false),
                        icon: const Icon(Icons.album_outlined, size: 18),
                        label: Text(context.tr('show_artwork')),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showLyrics = true),
                        icon: const Icon(Icons.lyrics_outlined, size: 18),
                        label: Text(context.tr('show_lyrics')),
                      ),
                    ),
                  _buildTitle(item, scheme),
                  const SizedBox(height: AppSpacing.s4),
                  _buildSeekBar(),
                  const SizedBox(height: AppSpacing.s2),
                  _buildTransport(),
                  const SizedBox(height: AppSpacing.s4),
                  _buildExtras(scheme),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildArtwork(ProfileMediaItem item, double size) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = item.thumbnailUrl;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.s6),
        child: SizedBox(
          width: size,
          height: size,
          // Local songs carry their embedded art on the item, so a device track
          // finally shows its real cover instead of the gradient placeholder.
          // Network results (YouTube) keep using the thumbnail URL.
          child: item.artwork != null
              ? Image.memory(
                  item.artwork!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _artworkFallback(scheme),
                )
              : thumb != null && thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _artworkFallback(scheme),
                    )
                  : _artworkFallback(scheme),
        ),
      ),
    );
  }

  Widget _artworkFallback(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              scheme.tertiary,
            ],
          ),
        ),
        child: const Icon(Icons.music_note, size: 96, color: Colors.white70),
      );

  Widget _buildLyrics() => DsLyricsView(
        lyrics: _lyrics,
        loading: _loadingLyrics,
        position: _media.position,
        isPlaying: _media.isPlaying,
        onSeek: _media.seekTo,
        emptyTitle: context.tr('no_lyrics_title'),
        emptyBody: context.tr('no_lyrics_body'),
        instrumentalTitle: context.tr('instrumental_track'),
        noSyncedHint: context.tr('no_lyrics_body'),
      );

  Widget _buildTitle(ProfileMediaItem item, ColorScheme scheme) {
    final (track, artist) = _splitTitleArtist(item);
    return Column(
      children: [
        Text(
          track,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (artist.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s1),
          Text(
            artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.brandTextSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildSeekBar() => StreamBuilder<Duration>(
        stream: _media.positionStream,
        initialData: Duration.zero,
        builder: (context, posSnap) {
          return StreamBuilder<Duration>(
            stream: _media.durationStream,
            initialData: Duration.zero,
            builder: (context, durSnap) {
              final total = durSnap.data ?? Duration.zero;
              final live = posSnap.data ?? Duration.zero;
              final value = _dragging ? _dragPosition : live;
              final maxMs = total.inMilliseconds.toDouble();
              final canSeek = total > Duration.zero;
              return Column(
                children: [
                  Slider(
                    value: maxMs <= 0
                        ? 0
                        : value.inMilliseconds.toDouble().clamp(0.0, maxMs),
                    max: maxMs <= 0 ? 1 : maxMs,
                    onChanged: canSeek
                        ? (v) => setState(() {
                              _dragging = true;
                              _dragPosition =
                                  Duration(milliseconds: v.round());
                            })
                        : null,
                    onChangeEnd: canSeek
                        ? (v) {
                            final target =
                                Duration(milliseconds: v.round());
                            setState(() => _dragging = false);
                            _media.seekTo(target);
                          }
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _clock(value),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          _clock(total),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

  Widget _buildTransport() => StreamBuilder<ProfileMediaState>(
        stream: _media.stateStream,
        builder: (context, snap) {
          final playing = _media.isPlaying ||
              snap.data == ProfileMediaState.playing;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 32,
                tooltip: 'Previous',
                onPressed:
                    _media.queue.length > 1 ? _media.previous : null,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton.filled(
                iconSize: 44,
                style: IconButton.styleFrom(
                  minimumSize: const Size(72, 72),
                ),
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: _media.toggle,
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  size: 40,
                ),
              ),
              IconButton(
                iconSize: 32,
                tooltip: 'Next',
                onPressed: _media.queue.length > 1 ? _media.next : null,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          );
        },
      );

  Widget _buildExtras(ColorScheme scheme) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          StreamBuilder<double>(
            stream: _media.speedStream,
            initialData: 1.0,
            builder: (context, snap) {
              final speed = snap.data ?? 1.0;
              final whole = speed == speed.roundToDouble();
              return TextButton(
                onPressed: _media.cycleSpeed,
                child: Text(
                  whole ? '${speed.toInt()}x' : '${speed}x',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
          StreamBuilder<QueueRepeatMode>(
            stream: _media.repeatStream,
            initialData: QueueRepeatMode.all,
            builder: (context, snap) {
              final mode = snap.data ?? QueueRepeatMode.all;
              final IconData icon;
              if (mode == QueueRepeatMode.one) {
                icon = Icons.repeat_one;
              } else if (mode == QueueRepeatMode.off) {
                icon = Icons.trending_flat;
              } else {
                icon = Icons.repeat;
              }
              return IconButton(
                tooltip: mode.name,
                onPressed: _media.cycleQueueRepeatMode,
                icon: Icon(
                  icon,
                  color: mode == QueueRepeatMode.off
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
              );
            },
          ),
          StreamBuilder<bool>(
            stream: _media.mutedStream,
            initialData: false,
            builder: (context, snap) {
              final muted = snap.data ?? false;
              return IconButton(
                tooltip: muted
                    ? context.tr('unmute')
                    : context.tr('mute'),
                onPressed: _media.toggleMute,
                icon: Icon(
                  muted ? Icons.volume_off : Icons.volume_up,
                  color: muted ? scheme.error : scheme.onSurfaceVariant,
                ),
              );
            },
          ),
          StreamBuilder<Duration?>(
            stream: _media.sleepStream,
            builder: (context, snap) {
              final remaining = snap.data;
              return IconButton(
                tooltip: context.tr('sleep_timer'),
                onPressed: _pickSleepTimer,
                icon: Icon(
                  remaining != null
                      ? Icons.bedtime
                      : Icons.bedtime_outlined,
                  color: remaining != null
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ],
      );

  Future<void> _pickSleepTimer() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.tr('cancel')),
              onTap: () => Navigator.pop(context),
            ),
            for (final m in const [15, 30, 45, 60])
              ListTile(
                title: Text('$m min'),
                onTap: () => Navigator.pop(context, m),
              ),
            ListTile(
              title: Text(context.tr('sleep_off')),
              onTap: () => Navigator.pop(context, 0),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 0) {
      _media.cancelSleepTimer();
      return;
    }
    _media.setSleepTimer(Duration(minutes: choice));
  }

  void _openQueue() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final queue = _media.queue;
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: queue.length,
            itemBuilder: (context, i) => ListTile(
              selected: i == _media.index,
              leading: Icon(i == _media.index
                  ? Icons.equalizer
                  : Icons.music_note_outlined),
              title: Text(
                queue[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                _media.playAt(i);
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
    );
  }
}