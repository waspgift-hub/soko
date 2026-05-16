import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../models/status_model.dart';
import '../../services/status_service.dart';
import '../../extensions/context_tr.dart';

class StatusViewerScreen extends StatefulWidget {
  final List<StatusUpdate> updates;
  final int initialIndex;

  const StatusViewerScreen({
    super.key,
    required this.updates,
    this.initialIndex = 0,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with TickerProviderStateMixin {
  late int _currentIndex;
  Timer? _autoAdvanceTimer;
  AnimationController? _progressController;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPaused = false;
  final StatusService _statusService = StatusService();
  final double _progressBarHeight = 3;
  final Duration _textImageDuration = const Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _currentIndex = widget.initialIndex.clamp(0, widget.updates.length - 1);
    _markViewed();
    _loadCurrentStatus();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _progressController?.dispose();
    _videoController?.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<void> _markViewed() async {
    try {
      await _statusService.markStatusViewed(widget.updates[_currentIndex].id);
    } catch (_) {}
  }

  Future<void> _loadCurrentStatus() async {
    _autoAdvanceTimer?.cancel();
    _progressController?.dispose();
    await _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;

    final status = widget.updates[_currentIndex];

    if (status.type == 'video' && status.mediaUrl != null) {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(status.mediaUrl!),
      );
      try {
        await _videoController!.initialize();
        if (!mounted) return;
        _videoController!.play();
        _isVideoInitialized = true;
        _videoController!.addListener(_onVideoPositionChange);
        setState(() {});
      } catch (e) {
        debugPrint('Video init error: $e');
        _startAutoAdvance(_textImageDuration);
      }
    } else {
      _startAutoAdvance(_textImageDuration);
    }

    if (mounted) setState(() {});
  }

  void _onVideoPositionChange() {
    if (!mounted || _videoController == null) return;
    final duration = _videoController!.value.duration;
    final position = _videoController!.value.position;
    if (position >= duration) {
      _goToNext();
    }
  }

  void _startAutoAdvance(Duration duration) {
    _autoAdvanceTimer?.cancel();
    _progressController?.dispose();
    _progressController = AnimationController(
      vsync: this,
      duration: duration,
    );
    _progressController!.forward();
    _autoAdvanceTimer = Timer(duration, () {
      if (mounted && !_isPaused) {
        _goToNext();
      }
    });
  }

  void _goToNext() {
    if (_currentIndex < widget.updates.length - 1) {
      setState(() => _currentIndex++);
      _markViewed();
      _loadCurrentStatus();
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _markViewed();
      _loadCurrentStatus();
    }
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _autoAdvanceTimer?.cancel();
      _progressController?.stop();
      _videoController?.pause();
    } else {
      _videoController?.play();
      if (widget.updates[_currentIndex].type != 'video') {
        final elapsed = (_progressController?.value ?? 0) * _textImageDuration.inMilliseconds;
        final remaining = Duration(milliseconds: (_textImageDuration.inMilliseconds - elapsed).clamp(0, _textImageDuration.inMilliseconds).toInt());
        if (remaining.inMilliseconds > 0) {
          _autoAdvanceTimer = Timer(remaining, () {
            if (mounted && !_isPaused) _goToNext();
          });
          _progressController = AnimationController(
            vsync: this,
            duration: remaining,
          );
          _progressController!.forward();
        } else {
          _goToNext();
        }
      }
    }
  }

  double _videoProgress() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return 0;
    }
    return _videoController!.value.position.inMilliseconds /
        _videoController!.value.duration.inMilliseconds;
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return context.tr('just_now');
    if (diff.inHours < 1) return '${diff.inMinutes} ${context.tr('minutes_ago')}';
    if (diff.inHours < 24) return '${diff.inHours} ${context.tr('hours_ago')}';
    return '${diff.inDays} ${context.tr('days_ago')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.updates[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTapDown: (_) => _togglePause(),
              onTapUp: (_) => _togglePause(),
              child: Dismissible(
                key: const ValueKey('status_dismiss'),
                direction: DismissDirection.down,
                dismissThresholds: const {
                  DismissDirection.down: 0.15,
                },
                onDismissed: (_) {
                  if (mounted) Navigator.pop(context);
                },
                child: Stack(
                  children: [
                    _buildContent(status),
                    GestureDetector(
                      onTap: () => _goToPrevious(),
                      child: Container(
                        width: MediaQuery.of(context).size.width / 2,
                        color: Colors.transparent,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: MediaQuery.of(context).size.width / 2,
                      child: GestureDetector(
                        onTap: () => _goToNext(),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildProgressBars(),
            _buildHeader(status),
            _buildFooter(status),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBars() {
    final padding = const EdgeInsets.only(top: 8, left: 8, right: 8);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: padding,
        child: Row(
          children: List.generate(widget.updates.length, (index) {
            final isPast = index < _currentIndex;
            final isCurrent = index == _currentIndex;

            double progress = 0;
            if (isPast) {
              progress = 1;
            } else if (isCurrent) {
              if (widget.updates[index].type == 'video' &&
                  _videoController != null &&
                  _videoController!.value.isInitialized) {
                progress = _videoProgress();
              } else {
                progress = _progressController?.value ?? 0;
              }
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: _progressBarHeight,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCurrent
                          ? Colors.white
                          : (isPast
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHeader(StatusUpdate status) {
    return Positioned(
      top: 20,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              backgroundImage: status.userImage != null
                  ? CachedNetworkImageProvider(status.userImage!)
                  : null,
              child: status.userImage == null
                  ? Text(
                      status.userName.isNotEmpty
                          ? status.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _timeAgo(status.createdAt),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(StatusUpdate status) {
    switch (status.type) {
      case 'image':
        return _buildImageContent(status);
      case 'video':
        return _buildVideoContent(status);
      case 'text':
      default:
        return _buildTextContent(status);
    }
  }

  Widget _buildImageContent(StatusUpdate status) {
    return Center(
      child: status.mediaUrl != null
          ? CachedNetworkImage(
              imageUrl: status.mediaUrl!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (context, url, error) => Center(
                child: Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            )
          : Center(
              child: Icon(
                Icons.image_not_supported,
                size: 64,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
    );
  }

  Widget _buildVideoContent(StatusUpdate status) {
    if (_videoController != null && _isVideoInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    }
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildTextContent(StatusUpdate status) {
    final colors = [
      const Color(0xFF2D6A4F),
      const Color(0xFF40916C),
      const Color(0xFF1B4332),
      const Color(0xFF52796F),
      const Color(0xFF84A98C),
      const Color(0xFF354F52),
      const Color(0xFF6B705C),
      const Color(0xFFA5A58D),
    ];
    final colorIndex = status.id.hashCode.abs() % colors.length;
    final bgColor = colors[colorIndex];

    return Container(
      color: bgColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            status.textContent ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(StatusUpdate status) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.4),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.visibility,
              size: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              '${status.viewers.length} ${context.tr('status_views')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const Spacer(),
            if (status.hasText && status.type != 'text')
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    status.textContent ?? '',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
