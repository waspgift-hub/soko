import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
// RepeatMode also exists in flutter/material (AnimationController); hide it so
// QueueRepeatMode usages below resolve without a prefix.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../extensions/context_tr.dart';
import '../models/product_model.dart';
import '../services/profile_media_controller.dart';
import '../services/profile_media_session.dart';
import '../services/youtube_utils.dart';

/// Media player section for the seller profile screen.
///
/// Streams the seller's products, keeps every listing that carries a video,
/// and plays them as a queue (featured player + up-next rail). Playback state
/// lives in [ProfileMediaController] — the Namida-style split of engine vs.
/// widgets — so the section hides itself when there is nothing playable and
/// never restarts playback on unrelated product-list refreshes.
class ProfileMediaSection extends StatelessWidget {
  final Stream<List<Product>> productsStream;
  final String sellerId;
  final String sellerName;

  const ProfileMediaSection({
    super.key,
    required this.productsStream,
    required this.sellerId,
    this.sellerName = '',
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: productsStream,
      builder: (context, snap) {
        final items = (snap.data ?? [])
            .where((p) => (p.videoUrl ?? '').isNotEmpty)
            .map(
              (p) => ProfileMediaItem(
                id: p.id,
                title: p.name,
                videoUrl: p.videoUrl!,
                thumbnailUrl: p.images.isNotEmpty ? p.images.first : null,
              ),
            )
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return SessionMediaPlayer(
          key: ValueKey(items.map((e) => e.id).join(',')),
          items: items,
          sellerId: sellerId,
          sellerName: sellerName,
        );      },
    );
  }
}

/// Shared inline player driven by the session controller (Namida miniplayer
/// architecture: one engine, many surfaces). Pass [items] to load a seller
/// queue; pass null to follow whatever the session is already playing (music
/// now-playing screen). Empty live queue renders a placeholder.
class SessionMediaPlayer extends StatefulWidget {
  final List<ProfileMediaItem>? items;
  final String sellerId;
  final String sellerName;

  const SessionMediaPlayer({
    super.key,
    required this.items,
    required this.sellerId,
    this.sellerName = '',
  });

  @override
  State<SessionMediaPlayer> createState() => SessionMediaPlayerState();
}

class SessionMediaPlayerState extends State<SessionMediaPlayer> {
  ProfileMediaController get _media => ProfileMediaSession.instance.controller;
  StreamSubscription<Duration>? _posSub;
  Duration _lastPosition = Duration.zero;
  Timer? _seekTimer;
  int _seekFeedback = 0;
  bool _seekForward = true;
  bool _ytExpanded = false;

  @override
  void initState() {
    super.initState();
    ProfileMediaSession.instance.enterInlinePlayer();
    _posSub = _media.positionStream.listen((p) => _lastPosition = p);
    _syncQueue(null, widget.items);
  }

  @override
  void didUpdateWidget(SessionMediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncQueue(oldWidget.items, widget.items);
  }

  /// Pushes [items] into the session when this surface owns the queue (seller
  /// profile). Null means "follow the live session queue" (now-playing), so
  /// nothing is loaded here — the caller already set it.
  void _syncQueue(
    List<ProfileMediaItem>? before,
    List<ProfileMediaItem>? after,
  ) {
    if (after == null) return;
    final oldIds = (before ?? const <ProfileMediaItem>[])
        .map((e) => e.id)
        .join(',');
    final newIds = after.map((e) => e.id).join(',');
    if (oldIds == newIds && before != null) return;
    ProfileMediaSession.instance.playSellerQueue(
      sellerId: widget.sellerId,
      sellerName: widget.sellerName,
      items: after,
    );
  }

  /// The queue this surface renders: the owned list, or the live session
  /// queue when following (music now-playing).
  List<ProfileMediaItem> get _effectiveItems =>
      widget.items ?? _media.queue;

  @override
  void dispose() {
    _posSub?.cancel();
    _seekTimer?.cancel();
    // Shared session controller outlives this screen for the mini player.
    ProfileMediaSession.instance.exitInlinePlayer();
    super.dispose();
  }

  /// Double-tap seek ported from Namida's video_widget.dart (_onDoubleTap).
  /// Left half seeks back, right half seeks forward, the middle sixth is
  /// ignored so center taps never seek by accident. Repeats inside a 900ms
  /// window accumulate into a single "+20s" style label.
  void _onDoubleTapSeek(Offset localPosition) {
    final width = MediaQuery.of(context).size.width - 32;
    final pos = localPosition.dx - width / 2;
    if (pos.abs() <= width / 6) return;
    final forward = !pos.isNegative;
    const step = Duration(seconds: 10);
    _media.seekBy(forward ? step : -step);
    setState(() {
      if (_seekTimer?.isActive != true || _seekForward != forward) {
        _seekFeedback = 0;
      }
      _seekForward = forward;
      _seekFeedback += 10;
    });
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _seekFeedback = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_effectiveItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            context.tr('no_music'),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                context.tr('profile_media'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_effectiveItems.length}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStage(context)
              .animate()
              .fadeIn(duration: 250.ms)
              .slideY(begin: 0.05, end: 0, duration: 300.ms, curve: Curves.easeOut),
          const SizedBox(height: 4),
          _buildSeekBar(context),
          _buildControls(context),
          _buildUpNext(context),
        ],
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Colors.black,
        height: MediaQuery.of(context).size.width * 9 / 16,
        child: StreamBuilder<int>(
          stream: _media.indexStream,
          initialData: _media.index,
          builder: (context, _) {
            final item = _media.current;
            if (item != null && item.isYouTube) {
              return _buildYouTubeStage(item);
            }
            if (item != null && item.isAudio) {
              return _buildAudioStage(item);
            }
            final vc = _media.video;
            if (vc == null) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
            }
            return ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: vc,
              builder: (context, value, _) {
                if (!value.isInitialized) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
                }
                return GestureDetector(
                  onTap: _media.toggle,
                  onDoubleTapDown: (details) => _onDoubleTapSeek(details.localPosition),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: value.size.width,
                          height: value.size.height,
                          child: VideoPlayer(vc),
                        ),
                      ),
                      if (!value.isPlaying)
                        const Center(
                          child: Icon(Icons.play_circle_fill, size: 56, color: Colors.white),
                        ),
                      if (_seekFeedback > 0)
                        Align(
                          alignment: _seekForward ? Alignment.centerRight : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _seekForward ? Icons.forward_10 : Icons.replay_10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_seekForward ? '+' : '-'}$_seekFeedback s',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      StreamBuilder<ProfileMediaState>(
                        stream: _media.stateStream,
                        builder: (context, stateSnap) {
                          if (stateSnap.data == ProfileMediaState.loading) {
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Artwork card for audio items. Same engine as video, but there is no
  /// picture to show, so the product thumbnail plus a live equalizer mark
  /// stand in. Tap toggles, double-tap seeks, exactly like video.
  Widget _buildAudioStage(ProfileMediaItem item) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _media.toggle,
      onDoubleTapDown: (details) => _onDoubleTapSeek(details.localPosition),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.30),
              Colors.black87,
            ],
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: item.thumbnailUrl != null
                        ? Image.network(item.thumbnailUrl!, fit: BoxFit.cover)
                        : Container(
                            color: Colors.black54,
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreamBuilder<ProfileMediaState>(
                        stream: _media.stateStream,
                        builder: (context, stateSnap) {
                          final playing =
                              stateSnap.data == ProfileMediaState.playing;
                          return Icon(
                            playing ? Icons.graphic_eq : Icons.music_note,
                            color: Colors.white,
                            size: 32,
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('audio_track'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_seekFeedback > 0)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_seekForward ? '+' : '-'}$_seekFeedback s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Embedded player for YouTube URLs. Mobile renders the nocookie iframe in
  /// a WebView; desktop and web fall back to the thumbnail + external launch
  /// because webview_flutter has no desktop implementation.
  bool get _isMobileEmbed => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Widget _buildYouTubeStage(ProfileMediaItem item) {
    final id = youTubeIdFromUrl(item.videoUrl);
    if (id == null) return const SizedBox.shrink();
    if (_ytExpanded) {
      return _ytThumbnail(item, dimmed: true);
    }
    if (_isMobileEmbed) {
      return _YouTubeEmbed(
        key: ValueKey(id),
        videoId: id,
        fallbackUrl: item.videoUrl,
        onEnded: _media.next,
      );
    }
    return _ytThumbnail(item, dimmed: false);
  }

  Widget _ytThumbnail(ProfileMediaItem item, {required bool dimmed}) {
    return GestureDetector(
      onTap: () => _openYouTubeExternal(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.thumbnailUrl != null)
            Image.network(item.thumbnailUrl!, fit: BoxFit.cover)
          else
            Container(color: Colors.black87),
          Container(color: Colors.black38),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: dimmed ? Colors.grey : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                ),
                if (!dimmed) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('watch_on_youtube'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openYouTubeExternal(ProfileMediaItem item) async {
    final uri = Uri.tryParse(item.videoUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildSeekBar(BuildContext context) {
    // The YouTube embed owns its own seekbar inside the iframe.
    return StreamBuilder<int>(
      stream: _media.indexStream,
      initialData: _media.index,
      builder: (context, _) {
        if (_media.isCurrentYouTube) return const SizedBox(height: 8);
        return _buildEngineSeekBar(context);
      },
    );
  }

  Widget _buildEngineSeekBar(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _media.positionStream,
      initialData: Duration.zero,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: _media.durationStream,
          initialData: Duration.zero,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final max = dur.inMilliseconds.toDouble();
            return Row(
              children: [
                Text(
                  _fmt(pos),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: max <= 0 ? 1 : max,
                    value: pos.inMilliseconds.toDouble().clamp(0, max <= 0 ? 1 : max),
                    onChanged: (v) => _media.seekTo(Duration(milliseconds: v.round())),
                  ),
                ),
                Text(
                  _fmt(dur),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<int>(
      stream: _media.indexStream,
      initialData: _media.index,
      builder: (context, idxSnap) {
        final item = _media.current;
        return Row(
          children: [
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.skip_previous),
              onPressed: _media.queue.length > 1 ? _media.previous : null,
            ),
            StreamBuilder<ProfileMediaState>(
              stream: _media.stateStream,
              builder: (context, stateSnap) {
                // isPlaying is synchronous and valid on both engines; the
                // stream keeps the button rebuilding as state changes.
                final playing = _media.isPlaying ||
                    stateSnap.data == ProfileMediaState.playing;
                return IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Play',
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _media.toggle,
                );
              },
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.skip_next),
              onPressed: _media.queue.length > 1 ? _media.next : null,
            ),
            Expanded(
              child: Text(
                item?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            StreamBuilder<double>(
              stream: _media.speedStream,
              initialData: 1.0,
              builder: (context, speedSnap) {
                if (_media.isCurrentYouTube) {
                  return const SizedBox.shrink();
                }
                final speed = speedSnap.data ?? 1.0;
                final whole = speed == speed.roundToDouble();
                return TextButton(
                  onPressed: _media.cycleSpeed,
                  child: Text(
                    whole ? '${speed.toInt()}x' : '${speed}x',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
            StreamBuilder<QueueRepeatMode>(
              stream: _media.repeatStream,
              initialData: QueueRepeatMode.all,
              builder: (context, repeatSnap) {
                final mode = repeatSnap.data ?? QueueRepeatMode.all;
                final IconData icon;
                Color? color = scheme.onSurfaceVariant;
                if (mode == QueueRepeatMode.one) {
                  icon = Icons.repeat_one;
                  color = scheme.primary;
                } else if (mode == QueueRepeatMode.all) {
                  icon = Icons.repeat;
                  color = scheme.primary;
                } else {
                  icon = Icons.repeat;
                }
                return IconButton(
                  tooltip: 'Repeat: ${mode.name}',
                  icon: Icon(icon),
                  color: color,
                  onPressed: _media.cycleQueueRepeatMode,
                );
              },
            ),
            StreamBuilder<Duration?>(
              stream: _media.sleepStream,
              builder: (context, sleepSnap) {
                final remaining = sleepSnap.data;
                final active = remaining != null;
                return IconButton(
                  tooltip: active
                      ? 'Sleep in ${_fmtSleep(remaining)} — tap to change'
                      : 'Sleep timer',
                  icon: Icon(active ? Icons.bedtime : Icons.bedtime_outlined),
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                  onPressed: _openSleepSheet,
                );
              },
            ),
            StreamBuilder<bool>(
              stream: _media.mutedStream,
              initialData: false,
              builder: (context, muteSnap) {
                final muted = muteSnap.data ?? false;
                return IconButton(
                  tooltip: muted ? 'Unmute' : 'Mute',
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  color: scheme.onSurfaceVariant,
                  onPressed: _media.toggleMute,
                );
              },
            ),
            if (item != null && !item.isAudio)
              IconButton(
                tooltip: 'Fullscreen',
                icon: const Icon(Icons.fullscreen),
                color: scheme.onSurfaceVariant,
                onPressed: () => _openFullscreen(item),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUpNext(BuildContext context) {
    final queue = _effectiveItems;
    if (queue.length < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          context.tr('up_next'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 92,
          child: StreamBuilder<int>(
            stream: _media.indexStream,
            initialData: _media.index,
            builder: (context, idxSnap) {
              final current = idxSnap.data ?? 0;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: queue.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final item = queue[i];
                  final active = i == current;
                  return AnimationConfiguration.staggeredList(
                    position: i,
                    duration: const Duration(milliseconds: 300),
                    child: SlideAnimation(
                      horizontalOffset: 40,
                      child: FadeInAnimation(
                        child: GestureDetector(
                          onTap: () => _media.playAt(i),
                          child: SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (item.thumbnailUrl != null)
                                          Image.network(item.thumbnailUrl!, fit: BoxFit.cover)
                                        else
                                          Container(color: Colors.black87),
                                        Container(color: Colors.black26),
                                        Center(
                                          child: Icon(
                                            active ? Icons.equalizer : Icons.play_arrow,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                        if (active)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: scheme.primary, width: 2),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openFullscreen(ProfileMediaItem item) async {
    if (item.isYouTube) {
      await _openYouTubeFullscreen(item);
      return;
    }
    await _media.pause();
    if (!mounted) return;
    final resumeAt = await Navigator.of(context).push<Duration>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenMedia(item: item, startAt: _lastPosition),
      ),
    );
    if (!mounted) return;
    if (resumeAt != null) await _media.seekTo(resumeAt);
    await _media.play();
  }

  Future<void> _openYouTubeFullscreen(ProfileMediaItem item) async {
    final id = youTubeIdFromUrl(item.videoUrl);
    if (id == null || !mounted) return;
    if (!_isMobileEmbed) {
      await _openYouTubeExternal(item);
      return;
    }
    // The iframe can't be paused from Dart, so the inline embed is parked on
    // its thumbnail while the dialog owns the only live WebView — otherwise
    // both instances would play audio at once. Rebuilding on close restarts
    // the inline video (autoplay is on), which beats double audio.
    setState(() => _ytExpanded = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (dialogContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: _YouTubeEmbed(
              videoId: id,
              fallbackUrl: item.videoUrl,
              onEnded: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() => _ytExpanded = false);
  }

  Future<void> _openSleepSheet() async {
    const options = [5, 10, 15, 30, 45, 60];
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.tr('sleep_timer')),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            for (final minutes in options)
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text('$minutes min'),
                onTap: () {
                  _media.setSleepTimer(Duration(minutes: minutes));
                  Navigator.of(sheetContext).pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.bedtime_off_outlined),
              title: Text(context.tr('sleep_off')),
              onTap: () {
                _media.cancelSleepTimer();
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fmtSleep(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m';
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

/// Nocookie YouTube iframe for mobile. Callers keep a single live instance —
/// the inline stage parks on a thumbnail while the fullscreen dialog owns
/// one — because the iframe can't be paused from Dart.
class _YouTubeEmbed extends StatefulWidget {
  final String videoId;
  final String fallbackUrl;
  final VoidCallback? onEnded;

  const _YouTubeEmbed({
    super.key,
    required this.videoId,
    required this.fallbackUrl,
    this.onEnded,
  });

  @override
  State<_YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<_YouTubeEmbed> {
  late final WebViewController _controller;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'YouTubeError',
        onMessageReceived: (msg) {
          if (mounted) setState(() => _errorCode = msg.message);
        },
      )
      ..addJavaScriptChannel(
        'YouTubeState',
        onMessageReceived: (msg) {
          if (msg.message == youTubeStateEnded) widget.onEnded?.call();
        },
      )
      ..loadHtmlString(youTubeEmbedHtml(widget.videoId));
  }

  @override
  Widget build(BuildContext context) {
    if (_errorCode != null) return _unplayableFallback();
    return WebViewWidget(controller: _controller);
  }

  /// Codes 101/150/153 all mean the same thing to a viewer: the owner or
  /// YouTube won't let this video play inside another app (this is the
  /// "video player configuration error" users used to see raw). Offer the
  /// official exit instead of a dead frame.
  Widget _unplayableFallback() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, color: Colors.white70, size: 40),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                context.tr('yt_unplayable'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                final uri = Uri.tryParse(widget.fallbackUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(context.tr('watch_on_youtube')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen playback on its own controller. The inline player is paused
/// while this route is up and resumes where the fullscreen player left off.
class _FullscreenMedia extends StatefulWidget {
  final ProfileMediaItem item;
  final Duration startAt;

  const _FullscreenMedia({required this.item, required this.startAt});

  @override
  State<_FullscreenMedia> createState() => _FullscreenMediaState();
}

class _FullscreenMediaState extends State<_FullscreenMedia> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.item.videoUrl))
      ..initialize()
          .then((_) async {
            if (!mounted) return;
            await _controller?.seekTo(widget.startAt);
            await _controller?.play();
            setState(() {});
          })
          .catchError((_) {
            if (mounted) setState(() => _failed = true);
          });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(c?.value.position),
        ),
      ),
      body: Center(
        child: _failed
            ? const Text('Video haijafunguka', style: TextStyle(color: Colors.white))
            : (c == null || !c.value.isInitialized)
            ? const CircularProgressIndicator(color: Colors.white)
            : GestureDetector(
                onTap: () {
                  c.value.isPlaying ? c.pause() : c.play();
                  setState(() {});
                },
                child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
              ),
      ),
    );
  }
}
