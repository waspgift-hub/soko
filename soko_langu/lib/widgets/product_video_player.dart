import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Inline video player used on product pages when a listing carries a video.
/// Lazy-initializes on first frame so the gallery stays responsive.
class ProductVideoPlayer extends StatefulWidget {
  final String url;

  const ProductVideoPlayer({super.key, required this.url});

  @override
  State<ProductVideoPlayer> createState() => _ProductVideoPlayerState();
}

class _ProductVideoPlayerState extends State<ProductVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
    )..initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {
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
    if (_failed) return const SizedBox.shrink();
    Widget child;
    if (c == null || !c.value.isInitialized) {
      child = const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    } else {
      child = GestureDetector(
        onTap: () {
          c.value.isPlaying ? c.pause() : c.play();
          setState(() {});
        },
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
              if (!c.value.isPlaying)
                Icon(
                  Icons.play_circle_fill,
                  size: 56,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      height: MediaQuery.of(context).size.width * 9 / 16,
      child: child,
    );
  }
}