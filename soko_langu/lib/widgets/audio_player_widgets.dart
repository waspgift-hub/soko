import 'dart:math';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../extensions/context_tr.dart';
import '../services/audio_player_service.dart';
import 'google_loading.dart';

String formatAudioDuration(Duration d) =>
    '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
    '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Bottom mini player — tap to open full screen.
class AudioMiniPlayer extends StatelessWidget {
  final VoidCallback onOpenFullPlayer;
  final bool showSeekBar;

  const AudioMiniPlayer({
    super.key,
    required this.onOpenFullPlayer,
    this.showSeekBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final audio = AudioPlayerService.instance;

    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final song = audio.currentSong;
        if (song == null) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;

        return Material(
          color: cs.surfaceContainerLow,
          elevation: 8,
          shadowColor: cs.primary.withValues(alpha: 0.15),
          child: InkWell(
            onTap: onOpenFullPlayer,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSeekBar && audio.duration > Duration.zero)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _MiniSeekBar(audio: audio),
                  ),
                SizedBox(
                  height: 68,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      _SongArtwork(song: song, size: 48, radius: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if ((song.artist ?? '').isNotEmpty)
                              Text(
                                song.artist!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (audio.isBuffering)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: GoogleLoading(size: 22, strokeWidth: 2),
                        )
                      else ...[
                        IconButton(
                          icon: const Icon(Icons.replay_10, size: 22),
                          onPressed: () =>
                              audio.seekRelative(const Duration(seconds: -10)),
                          visualDensity: VisualDensity.compact,
                        ),
                        _PlayPauseButton(audio: audio, size: 40, iconSize: 24),
                        IconButton(
                          icon: const Icon(Icons.forward_10, size: 22),
                          onPressed: () =>
                              audio.seekRelative(const Duration(seconds: 10)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniSeekBar extends StatelessWidget {
  final AudioPlayerService audio;

  const _MiniSeekBar({required this.audio});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? audio.position;
        final dur = audio.duration;
        final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();

        return Row(
          children: [
            Text(
              formatAudioDuration(pos),
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.onSurface.withValues(alpha: 0.15),
                  thumbColor: cs.primary,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: pos.inMilliseconds.toDouble().clamp(0.0, max).toDouble(),
                  max: max,
                  onChanged: (v) =>
                      audio.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
            ),
            Text(
              formatAudioDuration(dur),
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final AudioPlayerService audio;
  final double size;
  final double iconSize;

  const _PlayPauseButton({
    required this.audio,
    required this.size,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.85)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          audio.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: cs.onPrimary,
          size: iconSize,
        ),
        onPressed: audio.togglePlayPause,
      ),
    );
  }
}

class _SongArtwork extends StatelessWidget {
  final SongModel song;
  final double size;
  final double radius;

  const _SongArtwork({
    required this.song,
    required this.size,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: QueryArtworkWidget(
        id: song.id,
        type: ArtworkType.AUDIO,
        artworkFit: BoxFit.cover,
        artworkBorder: BorderRadius.circular(radius),
        size: size.round(),
        nullArtworkWidget: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.25),
                cs.primary.withValues(alpha: 0.08),
              ],
            ),
          ),
          child: Icon(Icons.music_note_rounded, color: cs.primary, size: size * 0.45),
        ),
      ),
    );
  }
}

/// Full-screen now playing UI.
class AudioFullPlayerPage extends StatefulWidget {
  final VoidCallback? onAddToPlaylist;

  const AudioFullPlayerPage({super.key, this.onAddToPlaylist});

  @override
  State<AudioFullPlayerPage> createState() => _AudioFullPlayerPageState();
}

class _AudioFullPlayerPageState extends State<AudioFullPlayerPage> {
  final AudioPlayerService _audio = AudioPlayerService.instance;
  bool _isSliding = false;
  double _slideValue = 0;

  void _openQueue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AudioQueuePage(
          songs: _audio.songs,
          currentIndex: _audio.currentIndex ?? 0,
          onPlay: (i) {
            _audio.playSong(i);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _audio,
      builder: (context, _) {
        final song = _audio.currentSong;
        if (song == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: Text(context.tr('now_playing')),
            ),
            body: Center(
              child: Text(
                context.tr('no_song_playing'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final cs = Theme.of(context).colorScheme;
        final artSize = min(300.0, MediaQuery.sizeOf(context).shortestSide * 0.72);

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.primary.withValues(alpha: 0.12),
                  cs.surface,
                  cs.surface,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            context.tr('now_playing'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.queue_music_rounded),
                          onPressed: _openQueue,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          const Spacer(),
                          Hero(
                            tag: 'audio_art_${song.id}',
                            child: Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.28),
                                    blurRadius: 36,
                                    spreadRadius: 4,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: _SongArtwork(
                                song: song,
                                size: artSize,
                                radius: 28,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            song.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            song.artist ?? context.tr('unknown_artist'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (widget.onAddToPlaylist != null) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: widget.onAddToPlaylist,
                              icon: const Icon(Icons.playlist_add, size: 20),
                              label: Text(context.tr('add_to_playlist')),
                            ),
                          ],
                          const Spacer(),
                          _FullSeekBar(
                            audio: _audio,
                            isSliding: _isSliding,
                            slideValue: _slideValue,
                            onSlideStart: (v) => setState(() {
                              _isSliding = true;
                              _slideValue = v;
                            }),
                            onSlideUpdate: (v) =>
                                setState(() => _slideValue = v),
                            onSlideEnd: (v) {
                              setState(() => _isSliding = false);
                              _audio.seek(Duration(milliseconds: v.toInt()));
                            },
                          ),
                          const SizedBox(height: 20),
                          _FullControls(audio: _audio),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FullSeekBar extends StatefulWidget {
  final AudioPlayerService audio;
  final bool isSliding;
  final double slideValue;
  final ValueChanged<double> onSlideStart;
  final ValueChanged<double> onSlideUpdate;
  final ValueChanged<double> onSlideEnd;

  const _FullSeekBar({
    required this.audio,
    required this.isSliding,
    required this.slideValue,
    required this.onSlideStart,
    required this.onSlideUpdate,
    required this.onSlideEnd,
  });

  @override
  State<_FullSeekBar> createState() => _FullSeekBarState();
}

class _FullSeekBarState extends State<_FullSeekBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_FullSeekBar old) {
    super.didUpdateWidget(old);
    if (widget.isSliding && !old.isSliding) {
      _glowController.forward();
    } else if (!widget.isSliding && old.isSliding) {
      _glowController.reverse();
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<Duration>(
      stream: widget.audio.positionStream,
      builder: (context, snap) {
        final pos = widget.isSliding
            ? Duration(milliseconds: widget.slideValue.toInt())
            : (snap.data ?? widget.audio.position);
        final dur = widget.audio.duration;
        final maxMs =
            dur.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
        final value =
            pos.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.onSurface.withValues(alpha: 0.12),
                thumbColor: cs.primary,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: widget.isSliding ? 9 : 7,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                overlayColor: cs.primary.withValues(alpha: 0.18),
              ),
              child: AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: widget.isSliding
                        ? BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(
                                    alpha: 0.3 * _glowAnimation.value),
                                blurRadius: 16 + 8 * _glowAnimation.value,
                                spreadRadius: 2 * _glowAnimation.value,
                              ),
                            ],
                          )
                        : null,
                    child: child,
                  );
                },
                child: Slider(
                  value: value,
                  max: maxMs,
                  onChangeStart: widget.onSlideStart,
                  onChanged: widget.onSlideUpdate,
                  onChangeEnd: widget.onSlideEnd,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isSliding
                          ? cs.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      formatAudioDuration(pos),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            widget.isSliding ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isSliding ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    formatAudioDuration(dur),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FullControls extends StatelessWidget {
  final AudioPlayerService audio;

  const _FullControls({required this.audio});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle_rounded,
            color: audio.shuffle ? cs.primary : cs.onSurfaceVariant,
          ),
          onPressed: () => audio.toggleShuffle(),
        ),
        IconButton(
          icon: Icon(Icons.skip_previous_rounded, color: cs.onSurface, size: 36),
          onPressed: audio.previous,
        ),
        _PlayPauseButton(audio: audio, size: 64, iconSize: 36),
        IconButton(
          icon: Icon(Icons.skip_next_rounded, color: cs.onSurface, size: 36),
          onPressed: audio.next,
        ),
        IconButton(
          icon: _repeatIcon(context, audio),
          onPressed: audio.cycleRepeat,
        ),
      ],
    );
  }

  Widget _repeatIcon(BuildContext context, AudioPlayerService audio) {
    final cs = Theme.of(context).colorScheme;
    final active = audio.repeatMode != PlayerRepeatMode.off;
    final color = active ? cs.primary : cs.onSurfaceVariant;

    if (audio.repeatMode == PlayerRepeatMode.one) {
      return Badge(
        label: const Text('1', style: TextStyle(fontSize: 8)),
        backgroundColor: cs.primary,
        child: Icon(Icons.repeat_one_rounded, color: color),
      );
    }
    return Icon(Icons.repeat_rounded, color: color);
  }
}

class _AudioQueuePage extends StatelessWidget {
  final List<SongModel> songs;
  final int currentIndex;
  final ValueChanged<int> onPlay;

  const _AudioQueuePage({
    required this.songs,
    required this.currentIndex,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('now_playing')),
      ),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = index == currentIndex;
          final cs = Theme.of(context).colorScheme;

          return ListTile(
            leading: _SongArtwork(song: song, size: 44, radius: 8),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                color: isCurrent ? cs.primary : null,
              ),
            ),
            subtitle: Text(
              song.artist ?? context.tr('unknown_artist'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: isCurrent
                ? Icon(Icons.graphic_eq_rounded, color: cs.primary)
                : null,
            onTap: isCurrent ? null : () => onPlay(index),
          );
        },
      ),
    );
  }
}

/// Search field for filtering local songs.
class AudioSearchField extends StatelessWidget {
  final String query;
  final ValueChanged<String> onChanged;
  final String? hint;

  const AudioSearchField({
    super.key,
    required this.query,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint ?? context.tr('search_songs'),
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => onChanged(''),
                )
              : null,
          filled: true,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}
