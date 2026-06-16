import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:go_router/go_router.dart';
import '../../services/audio_handler.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String? audioUrl;
  final String? title;
  final String? artist;
  final List<String>? urls;
  final List<String>? titles;
  final List<String>? artists;
  final List<String>? imageUrls;
  final int initialIndex;
  const AudioPlayerScreen({
    super.key,
    this.audioUrl,
    this.title,
    this.artist,
    this.urls,
    this.titles,
    this.artists,
    this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late SokoAudioHandler _handler;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _handler = SokoAudioHandler();
    _playbackSub = _handler.playbackState.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _mediaItemSub = _handler.mediaItem.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  Future<void> _init() async {
    if (widget.urls != null && widget.urls!.isNotEmpty) {
      await _handler.loadFromUrls(
        widget.urls!,
        title: widget.title,
        artist: widget.artist,
        titles: widget.titles,
        artists: widget.artists,
        imageUrls: widget.imageUrls,
        initialIndex: widget.initialIndex,
      );
    } else if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty) {
      await _handler.loadFromUrls(
        [widget.audioUrl!],
        title: widget.title,
        artist: widget.artist,
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _mediaItemSub?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0)
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GoogleLoading(size: 48),
              const SizedBox(height: 24),
              Text(
                context.tr('loading'),
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      );
    }

    // Get state from handler
    final playbackState = _handler.playbackState.value;
    final mediaItem = _handler.mediaItem.value;
    final isPlaying = playbackState.playing;
    final isBuffering =
        playbackState.processingState == AudioProcessingState.buffering;
    final position = playbackState.position;
    final duration = _handler.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final title = mediaItem?.title ?? widget.title ?? context.tr('audio');
    final artist = mediaItem?.artist ?? '';
    final albumArt = mediaItem?.artUri;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.surfaceContainerLow, cs.surface],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 1),
              // Album art with blurred background effect
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                  image: albumArt != null
                      ? DecorationImage(
                          image: NetworkImage(albumArt.toString()),
                          fit: BoxFit.cover,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.1),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      key: ValueKey(isPlaying),
                      size: 100,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Title and artist
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (artist.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  artist,
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              // Status text
              Text(
                isBuffering
                    ? 'Buffering...'
                    : (isPlaying ? 'Now Playing' : 'Paused'),
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 32),
              // Seek bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        activeTrackColor: cs.onSurface,
                        inactiveTrackColor: cs.surfaceContainerHighest,
                        thumbColor: cs.onSurface,
                        overlayColor: cs.onSurface.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (v) {
                          final newPos = Duration(
                            milliseconds: (duration.inMilliseconds * v).round(),
                          );
                          _handler.seek(newPos);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmt(position),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          Text(
                            _fmt(duration),
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shuffle
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: _handler.isShuffled
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.4),
                    ),
                    iconSize: 26,
                    onPressed: _handler.toggleShuffle,
                  ),
                  const SizedBox(width: 12),
                  // Previous
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.15),
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 28,
                      color: cs.onSurface,
                      onPressed: _handler.skipToPrevious,
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Play/Pause
                  GestureDetector(
                    onTap: _handler.togglePlayPause,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: cs.onPrimary,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Next
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.15),
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 28,
                      color: cs.onSurface,
                      onPressed: _handler.skipToNext,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Repeat
                  IconButton(
                    icon: Icon(
                      _handler.repeatMode == LoopMode.one
                          ? Icons.repeat_one_rounded
                          : _handler.repeatMode == LoopMode.all
                          ? Icons.repeat_rounded
                          : Icons.repeat_rounded,
                      color: _handler.repeatMode != LoopMode.off
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.4),
                    ),
                    iconSize: 26,
                    onPressed: _handler.cycleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Error state
              if (_handler.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Playback error',
                            style: TextStyle(color: cs.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Queue indicator
              if (_handler.sequenceState != null &&
                  _handler.sequenceState!.sequence.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Queue: ${(_handler.sequenceState!.currentIndex + 1)}/${_handler.sequenceState!.sequence.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.list, size: 18),
                        label: Text(
                          'View Queue',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => context.push(AppRoutes.audioQueue),
                      ),
                    ],
                  ),
                ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
