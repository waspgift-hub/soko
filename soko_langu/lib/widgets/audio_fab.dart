import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:audio_service/audio_service.dart';
import '../services/audio_handler.dart';
import '../app/routes.dart';
import '../app/router.dart' show rootNavigatorKey;

class AudioFab extends StatefulWidget {
  const AudioFab({super.key});

  @override
  State<AudioFab> createState() => _AudioFabState();
}

class _AudioFabState extends State<AudioFab>
    with SingleTickerProviderStateMixin {
  final SokoAudioHandler _handler = SokoAudioHandler();
  StreamSubscription? _stateSub;
  StreamSubscription? _mediaSub;
  double _top = 300;
  double _right = 16;

  @override
  void initState() {
    super.initState();
    _stateSub = _handler.playbackState.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _mediaSub = _handler.mediaItem.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _mediaSub?.cancel();
    super.dispose();
  }

  bool get _hasAudio {
    try {
      return _handler.queue.value.isNotEmpty &&
          _handler.mediaItem.value != null &&
          _handler.playbackState.value.processingState !=
              AudioProcessingState.idle;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAudio) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final minTop = topInset + 80.0;
    final maxTop = screenHeight - bottomInset - 80;

    return Positioned(
      top: _top.clamp(minTop, maxTop),
      right: _right,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _top = (_top + details.delta.dy).clamp(minTop, maxTop);
            _right = (_right - details.delta.dx).clamp(0, 40);
          });
        },
        onTap: () {
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null) {
            GoRouter.of(ctx).push(AppRoutes.audioPlayer);
          }
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.music_note_rounded,
            color: cs.surface,
            size: 28,
          ),
        ),
      ),
    );
  }
}
