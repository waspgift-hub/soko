import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/soko_media_item.dart';

/// Fullscreen local video player with auto-hiding controls, tap-to-toggle via
/// a browser-style black UI. Plays MediaStore videos (content://) and imported
/// files (file://).
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.item});
  final SokoMediaItem item;
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _ctrl;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = _buildController()..initialize().then((_) => setState(() {}));
    _startHideTimer();
  }

  VideoPlayerController _buildController() {
    final uri = Uri.parse(widget.item.uri);
    // Imported files are file:// paths; MediaStore items are content:// URIs.
    if (uri.scheme == 'file') {
      return VideoPlayerController.file(File.fromUri(uri));
    }
    return VideoPlayerController.contentUri(uri);
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _ctrl.value.isPlaying) setState(() => _showControls = false);
    });
  }

  void _togglePlayback() async {
    if (_ctrl.value.isPlaying) {
      await _ctrl.pause();
    } else {
      await _ctrl.play();
      _startHideTimer();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _startHideTimer();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ctrl.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _ctrl.value.aspectRatio,
                  child: VideoPlayer(_ctrl),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            // Controls overlay.
            if (_showControls)
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xA6000000),
                        Colors.transparent,
                        Color(0xA6000000),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top bar: back + title.
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Text(
                                widget.item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      // Center play/pause with a soft pulse.
                      GestureDetector(
                        onTap: _togglePlayback,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(
                            _ctrl.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      // Seek bar + times.
                      _buildSeekBar(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    if (!_ctrl.value.isInitialized) return const SizedBox.shrink();
    final dur = _ctrl.value.duration;
    final pos = _ctrl.value.position;
    final frac = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Text(
            _fmt(pos),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Expanded(
            child: Slider(
              value: frac.clamp(0.0, 1.0),
              activeColor: const Color(0xFF00C853),
              inactiveColor: Colors.white24,
              onChangeStart: (_) => _hideTimer?.cancel(),
              onChanged: (v) {
                _ctrl.seekTo(
                  Duration(milliseconds: (v * dur.inMilliseconds).round()),
                );
              },
              onChangeEnd: (_) => _startHideTimer(),
            ),
          ),
          Text(
            _fmt(dur),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}