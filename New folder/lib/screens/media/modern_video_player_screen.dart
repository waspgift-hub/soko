import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../extensions/context_tr.dart';

class ModernVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final bool isAsset;

  const ModernVideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.title = '',
    this.isAsset = false,
  });

  @override
  State<ModernVideoPlayerScreen> createState() =>
      _ModernVideoPlayerScreenState();
}

class _ModernVideoPlayerScreenState extends State<ModernVideoPlayerScreen> {
  late VideoPlayerController _controller;
  late Future<void> _initializeFuture;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isLiked = false;
  int _commentCount = 0;
  int _shareCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.isAsset
        ? VideoPlayerController.asset(widget.videoUrl)
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _initializeFuture = _controller.initialize();
    _controller.addListener(_onControllerUpdate);
    _controller.setLooping(false);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startHideTimer();
    });
  }

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
      if (_controller.value.isPlaying) _startHideTimer();
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off,
                    color: Colors.white54,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('failed_to_load_video'),
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(context.tr('go_back')),
                  ),
                ],
              ),
            );
          }

          return GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              children: [
                // Full-screen video
                Center(
                  child: _controller.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        )
                      : const SizedBox.shrink(),
                ),

                // Gradient edge fade
                Positioned.fill(
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        Container(
                          height: MediaQuery.of(context).padding.top + 100,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black54, Colors.transparent],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 200,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black54],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Controls overlay
                if (_showControls) ...[
                  // Top bar
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

                  // Right side actions
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 100,
                    child: _buildRightActions(),
                  ),

                  // Center play/pause
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: AnimatedOpacity(
                        opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(),
                  ),
                ],

                // Tap hint (first play)
                if (!_controller.value.isInitialized)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 4,
            right: 16,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.title.isNotEmpty
                      ? widget.title
                      : context.tr('now_playing'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightActions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionButton(
            icon: _isLiked ? Icons.favorite : Icons.favorite_outline,
            color: _isLiked ? Colors.red : Colors.white,
            label: context.tr('like'),
            onTap: () => setState(() => _isLiked = !_isLiked),
          ),
          const SizedBox(height: 20),
          _actionButton(
            icon: Icons.chat_bubble_outline,
            color: Colors.white,
            label: '$_commentCount',
            onTap: () {
              setState(() => _commentCount++);
              _showControls = true;
              _startHideTimer();
            },
          ),
          const SizedBox(height: 20),
          _actionButton(
            icon: Icons.share_outlined,
            color: Colors.white,
            label: '$_shareCount',
            onTap: () {
              setState(() => _shareCount++);
            },
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              Row(
                children: [
                  Text(
                    _formatDuration(pos),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GestureDetector(
                        onTapDown: (details) {
                          final box = context.findRenderObject() as RenderBox;
                          final w = box.size.width - 56;
                          final ratio = (details.localPosition.dx - 16) / w;
                          final seekTo = (dur.inMilliseconds * ratio).toInt();
                          _controller.seekTo(
                            Duration(
                              milliseconds: seekTo.clamp(0, dur.inMilliseconds),
                            ),
                          );
                        },
                        child: Container(
                          height: 24,
                          alignment: Alignment.center,
                          child: Stack(
                            children: [
                              Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD8F3DC),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFD8F3DC,
                                        ).withOpacity(0.4),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left:
                                    (MediaQuery.of(context).size.width - 56) *
                                        progress.clamp(0.0, 1.0) -
                                    6,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD8F3DC),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFD8F3DC,
                                        ).withOpacity(0.6),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(dur),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Rewind 10s
                  _controlIcon(Icons.replay_10_rounded, () {
                    final p = _controller.value.position;
                    _controller.seekTo(
                      Duration(seconds: max(0, p.inSeconds - 10)),
                    );
                  }),
                  // Previous
                  _controlIcon(Icons.skip_previous_rounded, () {
                    _controller.seekTo(Duration.zero);
                  }),
                  // Play/Pause
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2D6A4F).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      iconSize: 32,
                      onPressed: _togglePlayPause,
                    ),
                  ),
                  // Forward 10s
                  _controlIcon(Icons.forward_10_rounded, () {
                    final p = _controller.value.position;
                    final d = _controller.value.duration;
                    _controller.seekTo(
                      Duration(seconds: min(d.inSeconds, p.inSeconds + 10)),
                    );
                  }),
                  // Next/restart
                  _controlIcon(Icons.skip_next_rounded, () {
                    _controller.seekTo(_controller.value.duration);
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlIcon(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 28),
      onPressed: onTap,
      splashRadius: 20,
    );
  }
}

