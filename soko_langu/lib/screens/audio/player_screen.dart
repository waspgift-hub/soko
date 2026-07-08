import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../providers/music_state_notifier.dart';
import '../../app/routes.dart';
import '../../services/music_theme_service.dart';
import '../../theme/app_animations.dart';
import '../../widgets/audio/animated_artwork.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _spinCtrl;
  late AnimationController _expandCtrl;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  final _colorService = MusicColorService();
  Color _vibrant = const Color(0xFF6366F1);
  Color _muted = const Color(0xFF8B5CF6);
  Color _darkVibrant = const Color(0xFF1E1B4B);
  bool _favorite = false;
  bool _showVolume = false;
  bool _isDraggingSeek = false;
  double _dragProgress = 0;
  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;
  int _doubleTapCount = 0;
  Timer? _doubleTapTimer;
  YoutubePlayerController? _ytController;
  StreamSubscription<YoutubePlayerValue>? _ytSub;
  String? _currentVideoId;
  bool _lastYtPlaying = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _expandCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.medium,
      value: 1.0,
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOutSine));
  }

  MusicStateNotifier? _lastNotifier;

  void _onNotifierChanged() {
    final state = _lastNotifier;
    if (state == null) return;
    _syncSpin(state.isPlaying);
    _syncYtPlayback(state.isPlaying);
    if (state.artUri != null) _extractColors(state.artUri.toString());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = context.read<MusicStateNotifier>();
    if (_lastNotifier != notifier) {
      _lastNotifier?.removeListener(_onNotifierChanged);
      _lastNotifier = notifier;
      notifier.addListener(_onNotifierChanged);
      _onNotifierChanged();
    }
  }

  @override
  void dispose() {
    _lastNotifier?.removeListener(_onNotifierChanged);
    _spinCtrl.dispose();
    _expandCtrl.dispose();
    _glowCtrl.dispose();
    _sleepTimer?.cancel();
    _doubleTapTimer?.cancel();
    _ytSub?.cancel();
    _ytController?.close();
    super.dispose();
  }

  void _syncSpin(bool isPlaying) {
    if (isPlaying && _spinCtrl.isDismissed) _spinCtrl.repeat();
    if (!isPlaying && _spinCtrl.isAnimating) _spinCtrl.stop();
  }

  Future<void> _extractColors(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final colors = await _colorService.extractColors(url);
      if (mounted)
        setState(() {
          _vibrant = colors.vibrant;
          _muted = colors.muted;
          _darkVibrant = colors.darkVibrant;
        });
    } catch (_) {}
  }

  void _handleDoubleTap() {
    _doubleTapCount++;
    if (_doubleTapCount == 1) {
      _doubleTapTimer = Timer(const Duration(milliseconds: 300), () {
        _doubleTapCount = 0;
      });
    } else if (_doubleTapCount >= 2) {
      setState(() => _favorite = !_favorite);
      _doubleTapCount = 0;
      _doubleTapTimer?.cancel();
      HapticFeedback.lightImpact();
    }
  }

  void _toggleSleepTimer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SleepTimerSheet(
        onSelect: (duration) {
          Navigator.pop(ctx);
          _sleepTimer?.cancel();
          if (duration == null) {
            setState(() => _sleepRemaining = Duration.zero);
            return;
          }
          _sleepRemaining = duration;
          _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            setState(() {
              _sleepRemaining -= const Duration(seconds: 1);
              if (_sleepRemaining <= Duration.zero) {
                t.cancel();
                context.read<MusicStateNotifier>().pause();
                _sleepRemaining = Duration.zero;
              }
            });
          });
        },
      ),
    );
  }

  void _showPlaybackSpeedSheet() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final notifier = context.read<MusicStateNotifier>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SpeedSheet(
        current: notifier.speed,
        speeds: speeds,
        onSelect: (speed) {
          Navigator.pop(ctx);
          notifier.setSpeed(speed);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<MusicStateNotifier>(
      builder: (context, state, _) {
        final isPlaying = state.isPlaying;
        final hasQueue = state.queueLength > 1;
        final progress = state.progress.clamp(0.0, 1.0);
        final pos = _isDraggingSeek
            ? Duration(
                milliseconds: (state.duration.inMilliseconds * _dragProgress)
                    .round(),
              )
            : state.position;
        final dur = state.duration;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.transparent,
            body: GestureDetector(
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! > 500) {
                  context.pop();
                }
              },
              onHorizontalDragEnd: (d) {
                if (d.primaryVelocity == null) return;
                if (d.primaryVelocity! < -300)
                  state.skipToNext();
                else if (d.primaryVelocity! > 300)
                  state.skipToPrevious();
              },
              child: Stack(
                children: [
                  _buildBackground(cs),
                  _buildBlurOverlay(),
                  SafeArea(
                    child: Column(
                      children: [
                        _buildAppBar(cs, state),
                        Expanded(
                          child: _buildContent(
                            cs,
                            state,
                            isPlaying,
                            hasQueue,
                            pos,
                            dur,
                            progress,
                          ),
                        ),
                      ],
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

  Widget _buildBackground(ColorScheme cs) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_vibrant, _muted, _darkVibrant, Colors.black],
          stops: const [0.0, 0.25, 0.6, 1.0],
        ),
      ),
    );
  }

  Widget _buildBlurOverlay() {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, _) {
          return BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: 60 * _glowAnim.value,
              sigmaY: 60 * _glowAnim.value,
            ),
            child: Container(color: Colors.transparent),
          );
        },
      ),
    );
  }

  Widget _buildAppBar(ColorScheme cs, MusicStateNotifier state) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 4,
        right: 4,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            onPressed: () => context.pop(),
          ),
          const Spacer(),
          Text(
            'NOW PLAYING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.queue_music_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            onPressed: () => context.push(AppRoutes.audioQueue),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    ColorScheme cs,
    MusicStateNotifier state,
    bool isPlaying,
    bool hasQueue,
    Duration pos,
    Duration dur,
    double progress,
  ) {
    final ytVideoId = state.youtubeVideoId;
    final hasYtVideo = ytVideoId != null && ytVideoId.isNotEmpty;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          if (hasYtVideo) ...[
            const SizedBox(height: 8),
            _buildYoutubeSection(cs, ytVideoId),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 8),
            GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: _buildArtwork(cs, state, isPlaying),
            ),
          ],
          const SizedBox(height: 32),
          _buildTitleSection(cs, state),
          const SizedBox(height: 28),
          _buildSeekBar(cs, pos, dur, progress),
          const SizedBox(height: 24),
          _buildControls(cs, state, isPlaying, hasQueue),
          const SizedBox(height: 20),
          _buildActionsRow(cs, state),
          if (_showVolume) _buildVolumeSlider(cs, state),
          if (_sleepRemaining > Duration.zero) _buildSleepIndicator(cs),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildYoutubeSection(ColorScheme cs, String? videoId) {
    if (videoId == null || videoId.isEmpty) return const SizedBox.shrink();
    if (_ytController == null || _currentVideoId != videoId) {
      _initYoutubeController(videoId);
    }
    if (_ytController == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _vibrant.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: YoutubePlayer(
          controller: _ytController!,
          aspectRatio: 16 / 9,
          backgroundColor: Colors.black,
        ),
      ),
    );
  }

  Widget _buildArtwork(
    ColorScheme cs,
    MusicStateNotifier state,
    bool isPlaying,
  ) {
    return Center(
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _vibrant.withValues(alpha: 0.25 * _glowAnim.value),
                  blurRadius: 60,
                  spreadRadius: 8,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: AnimatedArtwork(
              imageUrl: state.artUri?.toString(),
              size: 280,
              isPlaying: isPlaying,
              fallbackColor: _vibrant,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleSection(ColorScheme cs, MusicStateNotifier state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            state.title.isNotEmpty ? state.title : 'No track playing',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            state.artist.isNotEmpty ? state.artist : 'Unknown artist',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(
    ColorScheme cs,
    Duration pos,
    Duration dur,
    double progress,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          GestureDetector(
            onTapDown: (d) {
              final width = MediaQuery.of(context).size.width - 56;
              _dragProgress = (d.localPosition.dx / width).clamp(0.0, 1.0);
              setState(() => _isDraggingSeek = true);
            },
            onHorizontalDragStart: (_) =>
                setState(() => _isDraggingSeek = true),
            onHorizontalDragUpdate: (d) {
              final width = MediaQuery.of(context).size.width - 56;
              _dragProgress = (d.localPosition.dx / width).clamp(0.0, 1.0);
              setState(() {});
            },
            onHorizontalDragEnd: (_) {
              final notifier = context.read<MusicStateNotifier>();
              notifier.seek(
                Duration(
                  milliseconds: (dur.inMilliseconds * _dragProgress).round(),
                ),
              );
              setState(() => _isDraggingSeek = false);
            },
            child: CustomPaint(
              size: Size(double.infinity, 40),
              painter: _PremiumWaveformPainter(
                progress: _isDraggingSeek ? _dragProgress : progress,
                color: Colors.white,
                trackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: Colors.white,
                glowColor: _vibrant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(pos),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatDuration(dur),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    ColorScheme cs,
    MusicStateNotifier state,
    bool isPlaying,
    bool hasQueue,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shuffle
          _controlButton(
            Icons.shuffle_rounded,
            () => state.toggleShuffle(),
            isActive: state.shuffleEnabled,
            size: 22,
          ),
          const SizedBox(width: 8),
          // Previous
          _glassButton(
            Icons.skip_previous_rounded,
            hasQueue ? () => state.skipToPrevious() : null,
            32,
          ),
          const SizedBox(width: 16),
          // Play/Pause
          _playPauseButton(isPlaying, state),
          const SizedBox(width: 16),
          // Next
          _glassButton(
            Icons.skip_next_rounded,
            hasQueue ? () => state.skipToNext() : null,
            32,
          ),
          const SizedBox(width: 8),
          // Repeat
          _controlButton(
            state.repeatMode == 'one'
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            () => state.cycleRepeat(),
            isActive: state.repeatMode != 'off',
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _playPauseButton(bool isPlaying, MusicStateNotifier state) {
    return GestureDetector(
      onTap: () => state.togglePlayPause(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.white, Colors.white.withValues(alpha: 0.9)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.3),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: _vibrant.withValues(alpha: 0.2),
              blurRadius: 48,
              spreadRadius: 4,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: _vibrant,
          size: 42,
        ),
      ),
    );
  }

  Widget _glassButton(IconData icon, VoidCallback? onPressed, double size) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: onPressed != null ? 0.12 : 0.05),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: onPressed != null ? 0.15 : 0.05,
          ),
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: Colors.white.withValues(alpha: onPressed != null ? 0.9 : 0.2),
        ),
        iconSize: size,
        onPressed: onPressed,
        splashRadius: 24,
      ),
    );
  }

  Widget _controlButton(
    IconData icon,
    VoidCallback? onPressed, {
    bool isActive = true,
    double size = 22,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: size,
          color: Colors.white.withValues(alpha: isActive ? 0.7 : 0.3),
        ),
        onPressed: onPressed,
        splashRadius: 20,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildActionsRow(ColorScheme cs, MusicStateNotifier state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionIcon(
            _favorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
            color: _favorite
                ? Colors.pink
                : Colors.white.withValues(alpha: 0.6),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _favorite = !_favorite);
            },
          ),
          _actionIcon(Icons.lyrics_rounded, onPressed: () => _notYet(context)),
          _actionIcon(Icons.timer_outlined, onPressed: _toggleSleepTimer),
          _actionIcon(
            Icons.speed_rounded,
            onPressed: _showPlaybackSpeedSheet,
            isActive: state.speed != 1.0,
          ),
          _actionIcon(
            Icons.equalizer_rounded,
            onPressed: () => _notYet(context),
          ),
          _actionIcon(
            _showVolume ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            onPressed: () => setState(() => _showVolume = !_showVolume),
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(
    IconData icon, {
    Color? color,
    VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 20,
          color: color ?? Colors.white.withValues(alpha: isActive ? 0.9 : 0.55),
        ),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 20,
      ),
    );
  }

  Widget _buildVolumeSlider(ColorScheme cs, MusicStateNotifier state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.volume_down_rounded,
            color: Colors.white.withValues(alpha: 0.5),
            size: 16,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: state.volume,
                onChanged: (v) => state.setVolume(v),
              ),
            ),
          ),
          Icon(
            Icons.volume_up_rounded,
            color: Colors.white.withValues(alpha: 0.5),
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildSleepIndicator(ColorScheme cs) {
    final min = _sleepRemaining.inMinutes;
    final sec = _sleepRemaining.inSeconds.remainder(60);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            '${min}m ${sec}s',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _sleepTimer?.cancel();
              setState(() => _sleepRemaining = Duration.zero);
            },
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _notYet(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Coming soon...'),
        backgroundColor: Colors.white.withValues(alpha: 0.15),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _initYoutubeController(String? videoId) {
    debugPrint('[YT] _initYoutubeController called with videoId: $videoId');
    if (videoId == null || videoId.isEmpty) {
      _ytController?.close();
      _ytController = null;
      _currentVideoId = null;
      return;
    }
    if (videoId == _currentVideoId) {
      debugPrint('[YT] same videoId, skipping');
      return;
    }
    _ytController?.close();
    _ytController = null;
    _currentVideoId = videoId;
    debugPrint('[YT] creating controller for $videoId');
    _ytController = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: true,
        showControls: true,
        showFullscreenButton: true,
        enableJavaScript: true,
      ),
    );
    _ytSub?.cancel();
    _ytSub = _ytController!.listen((val) {
      debugPrint('[YT] state: ${val.playerState}, error: ${val.error}');
      if (val.error != null && val.error != YoutubeError.none) {
        debugPrint('[YT] player error: ${val.error}');
      }
    });
  }

  void _syncYtPlayback(bool isPlaying) {
    if (_ytController == null) return;
    if (isPlaying == _lastYtPlaying) return;
    _lastYtPlaying = isPlaying;
    if (isPlaying) {
      _ytController!.playVideo();
    } else {
      _ytController!.pauseVideo();
    }
  }
}

class _PremiumWaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final Color thumbColor;
  final Color glowColor;

  _PremiumWaveformPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.thumbColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final barCount = 60;
    final barWidth = size.width / barCount;
    final rng = math.Random(42);

    final paint = Paint()
      ..strokeWidth = barWidth * 0.45
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < barCount; i++) {
      final height = 2 + rng.nextInt(10);
      final x = i * barWidth + barWidth * 0.25;
      final isActive = i / barCount <= progress;

      paint.color = isActive ? color : trackColor;
      if (isActive && i == (progress * barCount).round()) {
        paint.color = glowColor;
      }

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }

    final thumbX = size.width * progress.clamp(0.0, 1.0);
    final thumbPaint = Paint()..color = thumbColor;
    canvas.drawCircle(Offset(thumbX, centerY), 6, thumbPaint);

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(thumbX, centerY), 12, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _PremiumWaveformPainter old) =>
      old.progress != progress || old.color != color;
}

class _SleepTimerSheet extends StatelessWidget {
  final void Function(Duration?) onSelect;
  const _SleepTimerSheet({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final options = [
      (Duration(minutes: 5), '5 minutes'),
      (Duration(minutes: 10), '10 minutes'),
      (Duration(minutes: 15), '15 minutes'),
      (Duration(minutes: 30), '30 minutes'),
      (Duration(hours: 1), '1 hour'),
      (Duration(hours: 2), '2 hours'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Sleep Timer',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          ...options.map(
            (o) => ListTile(
              title: Text(o.$2),
              leading: const Icon(Icons.timer_outlined),
              onTap: () => onSelect(o.$1),
            ),
          ),
          ListTile(
            title: Text('Turn off', style: TextStyle(color: cs.error)),
            leading: Icon(Icons.close, color: cs.error),
            onTap: () => onSelect(null),
          ),
        ],
      ),
    );
  }
}

class _SpeedSheet extends StatelessWidget {
  final double current;
  final List<double> speeds;
  final void Function(double) onSelect;
  const _SpeedSheet({
    required this.current,
    required this.speeds,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Playback Speed',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          ...speeds.map(
            (s) => ListTile(
              title: Text('${s}x'),
              trailing: s == current
                  ? Icon(Icons.check, color: cs.primary)
                  : null,
              onTap: () => onSelect(s),
            ),
          ),
        ],
      ),
    );
  }
}
