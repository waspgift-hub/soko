import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/media_player_service.dart';
import '../../theme/app_themes.dart';
import '../media/soko_artwork.dart';
import '../../screens/media/now_playing_screen.dart';

/// Persistent bar above the bottom nav showing the currently playing audio
/// track. Tapping the bar opens [NowPlayingScreen].
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});
  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: MediaPlayerService.instance.active ? 1.0 : 0.0,
    );
    _playingSub = MediaPlayerService.instance.playingStream.listen((_) {
      if (mounted) setState(() {});
    });
    MediaPlayerService.instance.addListener(_onPlayerChange);
  }

  void _onPlayerChange() {
    if (!mounted) return;
    final active = MediaPlayerService.instance.active;
    if (active && !_fadeCtrl.isCompleted) {
      _fadeCtrl.forward();
    } else if (!active && !_fadeCtrl.isDismissed) {
      _fadeCtrl.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    MediaPlayerService.instance.removeListener(_onPlayerChange);
    _playingSub?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = MediaPlayerService.instance;
    if (!player.active || player.current == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final brand = SokoColors.of(context);
    final item = player.current!;
    return FadeTransition(
      opacity: _fadeCtrl,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const NowPlayingScreen(),
            ),
          );
        },
        child: Container(
          height: 56,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              SokoArtwork(item: item, size: 40, radius: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Progress ring around play/pause for subtle progress feedback.
              StreamBuilder<Duration>(
                stream: player.positionStream,
                initialData: player.safePosition,
                builder: (context, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final dur = player.duration ?? Duration.zero;
                  final value = dur > Duration.zero
                      ? pos.inMilliseconds / dur.inMilliseconds
                      : 0.0;
                  return SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: value,
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(brand.commerce),
                          backgroundColor:
                              cs.outlineVariant.withValues(alpha: 0.2),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          icon: Icon(
                            player.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: cs.onSurface,
                          ),
                          onPressed: player.toggle,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}